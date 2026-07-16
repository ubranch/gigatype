use std::io;
use std::path::Path;

pub fn stage_ort_licenses(lib_location: &Path, destination: &Path) -> io::Result<()> {
    let source_root = lib_location.parent().ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "ORT_LIB_LOCATION has no parent directory: {}",
                lib_location.display()
            ),
        )
    })?;
    let destination_licenses = destination.join("licenses");
    std::fs::create_dir_all(&destination_licenses)?;

    for (source_name, destination_name) in [
        ("LICENSE", "onnxruntime-LICENSE.txt"),
        ("ThirdPartyNotices.txt", "onnxruntime-ThirdPartyNotices.txt"),
    ] {
        let source = source_root.join(source_name);
        if !source.is_file() {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                format!(
                    "required ONNX Runtime license is missing: {}",
                    source.display()
                ),
            ));
        }
        std::fs::copy(&source, destination_licenses.join(destination_name))?;
    }

    Ok(())
}

pub fn stage_cpu_ort_licenses(lib_location: &Path, destination: &Path) -> io::Result<()> {
    remove_stale_cuda_runtime(destination)?;
    stage_ort_licenses(lib_location, destination)
}

fn remove_stale_cuda_runtime(destination: &Path) -> io::Result<()> {
    let Ok(entries) = std::fs::read_dir(destination) else {
        return Ok(());
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let lower = entry.file_name().to_string_lossy().to_lowercase();
        let cuda_file = lower == "onnxruntime_providers_cuda.dll"
            || lower == "onnxruntime_providers_shared.dll"
            || lower == "third_party_notices-cuda.txt"
            || lower.starts_with("cublas")
            || lower.starts_with("cudart")
            || lower.starts_with("cufft")
            || lower.starts_with("cudnn")
            || lower.starts_with("nvrtc")
            || lower.starts_with("nvjitlink");
        if cuda_file {
            std::fs::remove_file(path)?;
        } else if lower == "licenses" && path.is_dir() {
            std::fs::remove_dir_all(path)?;
        }
    }
    Ok(())
}
