# Native Apple privacy manifest scope

UserDefaults CA92.1 covers app-owned preferences and local journal legacy keys on mobile and TV. Mobile migration/adoption accesses app-container file metadata (C617.1) and explicitly selected document-package metadata (3B52.1), retaining file stamps locally to detect concurrent changes. Migration checks local free capacity before writes (E174.1). None is used for fingerprinting or analytics. TV does not compile migration/adoption and declares only UserDefaults.

Source audit covered app, Playback, Core, Adoption, Diagnostics, Export and compiled Migration roots. Manifests report no developer/SDK collection or tracking; user-selected self-hosted server data is described in the Apple policy. This is distinct from the App Store privacy questionnaire, which remains to be saved in App Store Connect.

Approved reason definitions checked against [Apple's required reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), October 9, 2026.
