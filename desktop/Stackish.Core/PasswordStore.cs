using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Stackish.Core;

public interface IPasswordStore
{
    string Name { get; }
    string? Read(ConnectionSettings connection);
    void Write(ConnectionSettings connection, string password);
    void Delete(ConnectionSettings connection);
}

public static class PasswordStore
{
    public static IPasswordStore Create() => OperatingSystem.IsMacOS() ? new MacPasswordStore() :
        OperatingSystem.IsWindows() ? new WindowsPasswordStore() : throw new PlatformNotSupportedException();

    // Delimit with JSON; preserve case because database names and SQL logins can be case-sensitive.
    public static string Key(ConnectionSettings connection) => "Stackish/" + Convert.ToHexString(SHA256.HashData(
        Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new[]
        { connection.Server.Trim(), connection.Database.Trim(), connection.Username.Trim() }))));
}

internal sealed class WindowsPasswordStore : IPasswordStore
{
    public string Name => "Windows Credential Manager";
    private const uint Generic = 1, LocalMachine = 2;
    private const int NotFound = 1168;
    public string? Read(ConnectionSettings connection)
    {
        if (!CredReadW(PasswordStore.Key(connection), Generic, 0, out var pointer))
        {
            int error = Marshal.GetLastWin32Error();
            if (error == NotFound) return null;
            throw new Win32Exception(error);
        }
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            return credential.BlobSize == 0 ? "" : Marshal.PtrToStringUni(credential.Blob, checked((int)credential.BlobSize / 2));
        }
        finally { CredFree(pointer); }
    }
    public void Write(ConnectionSettings connection, string password)
    {
        byte[] bytes = Encoding.Unicode.GetBytes(password);
        var pointer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            var credential = new Credential { Type = Generic, TargetName = PasswordStore.Key(connection),
                UserName = connection.Username.Trim(), BlobSize = (uint)bytes.Length, Blob = pointer, Persist = LocalMachine };
            if (!CredWriteW(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            Marshal.FreeHGlobal(pointer);
        }
    }
    public void Delete(ConnectionSettings connection)
    {
        if (!CredDeleteW(PasswordStore.Key(connection), Generic, 0))
        {
            int error = Marshal.GetLastWin32Error();
            if (error != NotFound) throw new Win32Exception(error);
        }
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags, Type;
        public string? TargetName, Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint BlobSize;
        public IntPtr Blob;
        public uint Persist, AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias, UserName;
    }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredReadW(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredWriteW(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredDeleteW(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr credential);
}

internal sealed class MacPasswordStore : IPasswordStore
{
    public string Name => "macOS Keychain";
    private const string Security = "/System/Library/Frameworks/Security.framework/Security";
    private const string Core = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    private const int NotFound = -25300, Duplicate = -25299;
    private static readonly IntPtr SecurityLibrary = NativeLibrary.Load(Security);
    private static readonly IntPtr CoreLibrary = NativeLibrary.Load(Core);
    private static IntPtr Symbol(string name) => Marshal.ReadIntPtr(NativeLibrary.GetExport(
        name.StartsWith("kCF", StringComparison.Ordinal) ? CoreLibrary : SecurityLibrary, name));
    private static void Check(int status) { if (status != 0) throw new InvalidOperationException($"Keychain operation failed ({status})."); }

    public string? Read(ConnectionSettings connection)
    {
        using var query = Query(connection);
        query.Set("kSecReturnData", Symbol("kCFBooleanTrue"));
        int status = SecItemCopyMatching(query.Handle, out var data);
        if (status == NotFound) return null;
        Check(status);
        try
        {
            byte[] bytes = new byte[checked((int)CFDataGetLength(data))];
            try { Marshal.Copy(CFDataGetBytePtr(data), bytes, 0, bytes.Length); return JsonSerializer.Deserialize<string>(bytes) ?? throw new InvalidDataException("Invalid saved password format."); }
            finally { CryptographicOperations.ZeroMemory(bytes); }
        }
        finally { CFRelease(data); }
    }
    public void Write(ConnectionSettings connection, string password)
    {
        using var query = Query(connection);
        using var values = new Dictionary();
        // The login Keychain can ignore a zero-byte update. JSON encodes even an empty password as nonempty data.
        string encoded = JsonSerializer.Serialize(password);
        values.Data("kSecValueData", encoded);
        int status = SecItemUpdate(query.Handle, values.Handle);
        if (status == NotFound)
        {
            query.Data("kSecValueData", encoded);
            query.Text("kSecAttrLabel", "Stackish database password");
            status = SecItemAdd(query.Handle, IntPtr.Zero);
            if (status == Duplicate)
            {
                using var retry = Query(connection);
                status = SecItemUpdate(retry.Handle, values.Handle);
            }
        }
        Check(status);
    }
    public void Delete(ConnectionSettings connection)
    {
        using var query = Query(connection);
        int status = SecItemDelete(query.Handle);
        if (status != NotFound) Check(status);
    }
    private static Dictionary Query(ConnectionSettings connection)
    {
        var query = new Dictionary();
        query.Set("kSecClass", Symbol("kSecClassGenericPassword"));
        query.Text("kSecAttrService", "com.brentozar.stackish.database-password.v1");
        query.Text("kSecAttrAccount", PasswordStore.Key(connection));
        return query;
    }
    // Use CoreFoundation value equality for keys; release both dictionary and owned references.
    private sealed class Dictionary : IDisposable
    {
        public IntPtr Handle { get; } = CFDictionaryCreateMutable(IntPtr.Zero, 0,
            NativeLibrary.GetExport(CoreLibrary, "kCFTypeDictionaryKeyCallBacks"),
            NativeLibrary.GetExport(CoreLibrary, "kCFTypeDictionaryValueCallBacks"));
        private readonly List<IntPtr> owned = [];
        public void Set(string key, IntPtr value) => CFDictionarySetValue(Handle, Symbol(key), value);
        public void Text(string key, string value)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(value);
            var text = CFStringCreateWithBytes(IntPtr.Zero, bytes, bytes.Length, 0x08000100, false);
            owned.Add(text); Set(key, text);
        }
        public void Data(string key, string value)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(value);
            try { var data = CFDataCreate(IntPtr.Zero, bytes, bytes.Length); owned.Add(data); Set(key, data); }
            finally { CryptographicOperations.ZeroMemory(bytes); }
        }
        public void Dispose() { CFRelease(Handle); foreach (var value in owned) CFRelease(value); }
    }
    [DllImport(Security)] private static extern int SecItemCopyMatching(IntPtr query, out IntPtr result);
    [DllImport(Security)] private static extern int SecItemAdd(IntPtr attributes, IntPtr result);
    [DllImport(Security)] private static extern int SecItemUpdate(IntPtr query, IntPtr attributes);
    [DllImport(Security)] private static extern int SecItemDelete(IntPtr query);
    [DllImport(Core)] private static extern IntPtr CFDictionaryCreateMutable(IntPtr allocator, nint capacity, IntPtr keys, IntPtr values);
    [DllImport(Core)] private static extern void CFDictionarySetValue(IntPtr dictionary, IntPtr key, IntPtr value);
    [DllImport(Core)] private static extern IntPtr CFStringCreateWithBytes(IntPtr allocator, byte[] bytes, nint length, uint encoding, [MarshalAs(UnmanagedType.I1)] bool external);
    [DllImport(Core)] private static extern IntPtr CFDataCreate(IntPtr allocator, byte[] bytes, nint length);
    [DllImport(Core)] private static extern nint CFDataGetLength(IntPtr data);
    [DllImport(Core)] private static extern IntPtr CFDataGetBytePtr(IntPtr data);
    [DllImport(Core)] private static extern void CFRelease(IntPtr value);
}
