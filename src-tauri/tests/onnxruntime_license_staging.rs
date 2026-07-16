#[path = "../build_support.rs"]
mod build_support;

#[test]
fn stages_common_ort_license_and_notices() {
    let source_root = tempfile::tempdir().unwrap();
    let lib_dir = source_root.path().join("lib");
    std::fs::create_dir(&lib_dir).unwrap();
    std::fs::write(source_root.path().join("LICENSE"), b"license").unwrap();
    std::fs::write(source_root.path().join("ThirdPartyNotices.txt"), b"notices").unwrap();
    let destination = tempfile::tempdir().unwrap();

    build_support::stage_ort_licenses(&lib_dir, destination.path()).unwrap();

    assert_eq!(
        std::fs::read(destination.path().join("licenses/onnxruntime-LICENSE.txt")).unwrap(),
        b"license"
    );
    assert_eq!(
        std::fs::read(
            destination
                .path()
                .join("licenses/onnxruntime-ThirdPartyNotices.txt")
        )
        .unwrap(),
        b"notices"
    );
}

#[test]
fn cpu_staging_removes_cuda_metadata_and_keeps_common_ort_notices() {
    let source_root = tempfile::tempdir().unwrap();
    let lib_dir = source_root.path().join("lib");
    std::fs::create_dir(&lib_dir).unwrap();
    std::fs::write(source_root.path().join("LICENSE"), b"cpu license").unwrap();
    std::fs::write(
        source_root.path().join("ThirdPartyNotices.txt"),
        b"cpu notices",
    )
    .unwrap();

    let destination = tempfile::tempdir().unwrap();
    let licenses = destination.path().join("licenses");
    std::fs::create_dir(&licenses).unwrap();
    std::fs::write(licenses.join("cudnn-LICENSE.txt"), b"stale CUDA").unwrap();
    std::fs::write(
        destination.path().join("onnxruntime_providers_cuda.dll"),
        b"stale CUDA",
    )
    .unwrap();

    build_support::stage_cpu_ort_licenses(&lib_dir, destination.path()).unwrap();

    assert_eq!(
        std::fs::read(licenses.join("onnxruntime-LICENSE.txt")).unwrap(),
        b"cpu license"
    );
    assert_eq!(
        std::fs::read(licenses.join("onnxruntime-ThirdPartyNotices.txt")).unwrap(),
        b"cpu notices"
    );
    assert!(!licenses.join("cudnn-LICENSE.txt").exists());
    assert!(!destination
        .path()
        .join("onnxruntime_providers_cuda.dll")
        .exists());
}
