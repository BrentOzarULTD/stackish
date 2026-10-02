# App build delivery

Whenever app code or bundled SQL changes, deliver an updated built app before calling the work complete. A passing source build or tests alone is not delivery.

On Brent's Mac, the fixed testing location is `/Users/brentozar/Applications/Stackish.app`. Refresh that location with the current Apple Silicon build after signing, notarizing, and verifying the extracted package. Keep the last working copy until its replacement passes package verification. Launch the delivered copy and check the actual UI; report exactly what was tested and any limitations. Do not start a database workload merely to check that a build opens.

Keep a matching ZIP at `/Users/brentozar/Applications/Stackish-latest.zip` and build metadata at `/Users/brentozar/Applications/Stackish-build.txt` (source commit, build time, ZIP hash, verification performed). Update these same paths every time; do not make the user search versioned folders or draft releases. Never put credentials in build metadata.

This local testing copy does not replace the separate checks required for public releases or native Windows/Intel Mac validation. Do not claim those platforms were tested on Apple Silicon.

Brent explicitly authorized sending this and future compiled Stackish builds to Apple for notarization on October 2, 2026. Use the existing local signing identity and `Stackish-notary` Keychain profile; never export private keys or credentials.
