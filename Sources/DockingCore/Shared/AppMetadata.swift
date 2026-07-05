enum AppMetadata {
    // The app is intentionally pre-release. Keeping the version in one place
    // makes restore snapshots and generated bundles auditable without adding a
    // migration path for metadata formats that do not exist yet.
    static let version = "0.0.3"
}
