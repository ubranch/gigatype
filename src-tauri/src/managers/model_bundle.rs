use super::model::HuggingFaceBundleFile;
use anyhow::{bail, Context, Result};
use hf_hub::api::tokio::Progress;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BundlePaths {
    pub(crate) final_dir: PathBuf,
    pub(crate) staging_dir: PathBuf,
}

pub(crate) fn bundle_paths(models_dir: &Path, directory_name: &str) -> BundlePaths {
    BundlePaths {
        final_dir: models_dir.join(directory_name),
        staging_dir: models_dir.join(format!("{directory_name}.staging")),
    }
}

pub(crate) fn validate_bundle(
    repo_id: &str,
    revision: &str,
    files: &[HuggingFaceBundleFile],
) -> Result<()> {
    if repo_id.trim().is_empty() {
        bail!("Hugging Face bundle repo id must not be empty");
    }
    if revision.len() != 40 || !revision.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("Hugging Face bundle revision must be a 40-character commit SHA");
    }
    if files.is_empty() {
        bail!("Hugging Face bundle must contain at least one file");
    }

    let mut local_filenames = HashSet::with_capacity(files.len());
    for file in files {
        if file.remote_filename.trim().is_empty() {
            bail!("Hugging Face bundle remote filename must not be empty");
        }
        if file.local_filename.trim().is_empty() {
            bail!("Hugging Face bundle local filename must not be empty");
        }

        let local_path = Path::new(&file.local_filename);
        let mut components = local_path.components();
        let is_single_normal_component = matches!(components.next(), Some(Component::Normal(_)))
            && components.next().is_none()
            && !file.local_filename.contains(['/', '\\']);
        if local_path.is_absolute() || !is_single_normal_component {
            bail!(
                "Hugging Face bundle local filename must be a single path component: {}",
                file.local_filename
            );
        }
        if !local_filenames.insert(file.local_filename.as_str()) {
            bail!(
                "Hugging Face bundle has duplicate local filename: {}",
                file.local_filename
            );
        }
        if file.size_bytes == 0 {
            bail!(
                "Hugging Face bundle file must have a positive size: {}",
                file.remote_filename
            );
        }
        if file.sha256.len() != 64 || !file.sha256.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            bail!(
                "Hugging Face bundle SHA256 must contain exactly 64 hexadecimal characters: {}",
                file.remote_filename
            );
        }
    }

    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct BundleProgressSnapshot {
    pub(crate) downloaded: u64,
    pub(crate) total: u64,
    pub(crate) percentage: f64,
}

struct BundleProgressState {
    total: u64,
    completed: u64,
    current: u64,
    current_expected: u64,
    ready: bool,
}

type BundleProgressReporter = Arc<dyn Fn(BundleProgressSnapshot) + Send + Sync>;

#[derive(Clone)]
pub(crate) struct BundleProgressTracker {
    state: Arc<Mutex<BundleProgressState>>,
    report: BundleProgressReporter,
}

impl BundleProgressTracker {
    pub(crate) fn new(total: u64, report: BundleProgressReporter) -> Self {
        let tracker = Self {
            state: Arc::new(Mutex::new(BundleProgressState {
                total,
                completed: 0,
                current: 0,
                current_expected: 0,
                ready: false,
            })),
            report,
        };
        tracker.emit();
        tracker
    }

    fn snapshot(&self) -> BundleProgressSnapshot {
        let state = self.state.lock().unwrap();
        let downloaded = state
            .completed
            .saturating_add(state.current)
            .min(state.total);
        let percentage = if state.ready {
            100.0
        } else if state.total == 0 {
            0.0
        } else {
            ((downloaded as f64 / state.total as f64) * 100.0).min(99.9)
        };
        BundleProgressSnapshot {
            downloaded,
            total: state.total,
            percentage,
        }
    }

    fn emit(&self) {
        (self.report)(self.snapshot());
    }

    pub(crate) fn complete_cached(&self, size: u64) {
        {
            let mut state = self.state.lock().unwrap();
            state.completed = state.completed.saturating_add(size).min(state.total);
        }
        self.emit();
    }

    fn begin_file(&self, expected: u64) {
        {
            let mut state = self.state.lock().unwrap();
            state.current = 0;
            state.current_expected = expected;
        }
        self.emit();
    }

    fn advance_file(&self, size: u64) {
        {
            let mut state = self.state.lock().unwrap();
            state.current = state
                .current
                .saturating_add(size)
                .min(state.current_expected);
        }
        self.emit();
    }

    fn finish_file(&self) {
        {
            let mut state = self.state.lock().unwrap();
            let expected = state.current_expected;
            state.completed = state.completed.saturating_add(expected).min(state.total);
            state.current = 0;
            state.current_expected = 0;
        }
        self.emit();
    }

    pub(crate) fn mark_ready(&self) {
        {
            let mut state = self.state.lock().unwrap();
            state.completed = state.total;
            state.current = 0;
            state.current_expected = 0;
            state.ready = true;
        }
        self.emit();
    }

    pub(crate) fn file_progress(&self, expected: u64) -> BundleFileProgress {
        BundleFileProgress {
            tracker: self.clone(),
            expected,
        }
    }
}

#[derive(Clone)]
pub(crate) struct BundleFileProgress {
    tracker: BundleProgressTracker,
    expected: u64,
}

impl Progress for BundleFileProgress {
    async fn init(&mut self, _size: usize, _filename: &str) {
        self.tracker.begin_file(self.expected);
    }

    async fn update(&mut self, size: usize) {
        self.tracker.advance_file(size as u64);
    }

    async fn finish(&mut self) {
        self.tracker.finish_file();
    }
}

pub(crate) fn resolve_cached_files<F>(
    files: &[HuggingFaceBundleFile],
    mut lookup: F,
) -> Vec<Option<PathBuf>>
where
    F: FnMut(&str) -> Option<PathBuf>,
{
    files
        .iter()
        .map(|file| lookup(&file.remote_filename))
        .collect()
}

pub(crate) fn bundle_is_complete(final_dir: &Path, files: &[HuggingFaceBundleFile]) -> bool {
    if !final_dir.is_dir() {
        return false;
    }

    let Ok(entries) = fs::read_dir(final_dir) else {
        return false;
    };
    let mut seen = HashSet::with_capacity(files.len());
    for entry in entries.flatten() {
        let Some(name) = entry.file_name().to_str().map(str::to_string) else {
            return false;
        };
        let Some(file) = files.iter().find(|file| file.local_filename == name) else {
            return false;
        };
        let Ok(metadata) = entry.metadata() else {
            return false;
        };
        if !metadata.is_file() || metadata.len() != file.size_bytes || !seen.insert(name) {
            return false;
        }
    }

    seen.len() == files.len()
}

pub(crate) fn completed_bundle_path(
    models_dir: &Path,
    directory_name: &str,
    files: &[HuggingFaceBundleFile],
) -> Result<PathBuf> {
    let final_dir = bundle_paths(models_dir, directory_name).final_dir;
    if bundle_is_complete(&final_dir, files) {
        Ok(final_dir)
    } else {
        bail!("Complete model bundle not found: {directory_name}")
    }
}

fn remove_owned_path(path: &Path) -> Result<bool> {
    if path.is_dir() {
        fs::remove_dir_all(path)
            .with_context(|| format!("Failed to remove bundle directory {}", path.display()))?;
        Ok(true)
    } else if path.exists() {
        fs::remove_file(path)
            .with_context(|| format!("Failed to remove bundle file {}", path.display()))?;
        Ok(true)
    } else {
        Ok(false)
    }
}

pub(crate) fn cleanup_incomplete_bundle(models_dir: &Path, directory_name: &str) -> Result<bool> {
    let paths = bundle_paths(models_dir, directory_name);
    remove_owned_path(&paths.staging_dir)
}

pub(crate) fn delete_bundle(models_dir: &Path, directory_name: &str) -> Result<bool> {
    let paths = bundle_paths(models_dir, directory_name);
    let final_deleted = remove_owned_path(&paths.final_dir)?;
    let staging_deleted = remove_owned_path(&paths.staging_dir)?;
    Ok(final_deleted || staging_deleted)
}

pub(crate) fn hugging_face_cache_repo_root(path: &Path) -> Option<PathBuf> {
    path.ancestors()
        .find(|ancestor| {
            ancestor
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("models--"))
        })
        .map(Path::to_path_buf)
}

fn remove_corrupt_cache_state(path: &Path) -> Result<()> {
    if let Some(repo_root) = hugging_face_cache_repo_root(path) {
        fs::remove_dir_all(&repo_root).with_context(|| {
            format!(
                "Failed to clear corrupt Hugging Face cache repo {}",
                repo_root.display()
            )
        })?;
    } else if fs::symlink_metadata(path).is_ok() {
        fs::remove_file(path)
            .with_context(|| format!("Failed to clear corrupt cache file {}", path.display()))?;
    }
    Ok(())
}

fn compute_sha256(path: &Path) -> Result<String> {
    let mut file = File::open(path)
        .with_context(|| format!("Failed to open cached bundle file {}", path.display()))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 64 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .with_context(|| format!("Failed to read cached bundle file {}", path.display()))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn verify_cached_file(path: &Path, file: &HuggingFaceBundleFile) -> Result<()> {
    verify_cached_file_with_cleanup(path, file, remove_corrupt_cache_state)
}

fn verify_cached_file_with_cleanup<F>(
    path: &Path,
    file: &HuggingFaceBundleFile,
    cleanup: F,
) -> Result<()>
where
    F: FnOnce(&Path) -> Result<()>,
{
    let result = (|| {
        let actual_size = fs::metadata(path)
            .with_context(|| format!("Cached bundle file is missing: {}", path.display()))?
            .len();
        if actual_size != file.size_bytes {
            bail!(
                "Cached bundle size mismatch for {}: expected {}, got {}",
                file.remote_filename,
                file.size_bytes,
                actual_size
            );
        }

        let actual_sha256 = compute_sha256(path)?;
        if !actual_sha256.eq_ignore_ascii_case(&file.sha256) {
            bail!(
                "Cached bundle SHA256 mismatch for {}: expected {}, got {}",
                file.remote_filename,
                file.sha256,
                actual_sha256
            );
        }
        Ok(())
    })();

    match result {
        Ok(()) => Ok(()),
        Err(integrity_error) => match cleanup(path) {
            Ok(()) => Err(integrity_error),
            Err(cleanup_error) => Err(integrity_error.context(format!(
                "Failed to clear corrupt cache state: {cleanup_error:#}"
            ))),
        },
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MaterializationMode {
    HardLink,
    Copy,
    Mixed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BundlePrepareOutcome {
    Ready {
        materialization: MaterializationMode,
        reused: bool,
    },
    Cancelled,
}

struct StagingGuard {
    path: PathBuf,
    armed: bool,
}

impl Drop for StagingGuard {
    fn drop(&mut self) {
        if self.armed {
            let _ = remove_owned_path(&self.path);
        }
    }
}

pub(crate) fn prepare_bundle_from_cache(
    models_dir: &Path,
    directory_name: &str,
    files: &[HuggingFaceBundleFile],
    cached_paths: &[PathBuf],
    is_cancelled: &(dyn Fn() -> bool + Sync),
    progress: &BundleProgressTracker,
) -> Result<BundlePrepareOutcome> {
    prepare_bundle_from_cache_with_materializers(
        models_dir,
        directory_name,
        files,
        cached_paths,
        is_cancelled,
        progress,
        BundleMaterializers {
            linker: |source: &Path, destination: &Path| fs::hard_link(source, destination),
            copier: |source: &Path, destination: &Path| fs::copy(source, destination),
        },
    )
}

#[cfg(test)]
fn prepare_bundle_from_cache_with_linker<L>(
    models_dir: &Path,
    directory_name: &str,
    files: &[HuggingFaceBundleFile],
    cached_paths: &[PathBuf],
    is_cancelled: &(dyn Fn() -> bool + Sync),
    progress: &BundleProgressTracker,
    linker: L,
) -> Result<BundlePrepareOutcome>
where
    L: Fn(&Path, &Path) -> std::io::Result<()>,
{
    prepare_bundle_from_cache_with_materializers(
        models_dir,
        directory_name,
        files,
        cached_paths,
        is_cancelled,
        progress,
        BundleMaterializers {
            linker,
            copier: |source: &Path, destination: &Path| fs::copy(source, destination),
        },
    )
}

struct BundleMaterializers<L, C> {
    linker: L,
    copier: C,
}

fn prepare_bundle_from_cache_with_materializers<L, C>(
    models_dir: &Path,
    directory_name: &str,
    files: &[HuggingFaceBundleFile],
    cached_paths: &[PathBuf],
    is_cancelled: &(dyn Fn() -> bool + Sync),
    progress: &BundleProgressTracker,
    materializers: BundleMaterializers<L, C>,
) -> Result<BundlePrepareOutcome>
where
    L: Fn(&Path, &Path) -> std::io::Result<()>,
    C: Fn(&Path, &Path) -> std::io::Result<u64>,
{
    let paths = bundle_paths(models_dir, directory_name);
    if bundle_is_complete(&paths.final_dir, files) {
        progress.mark_ready();
        return Ok(BundlePrepareOutcome::Ready {
            materialization: MaterializationMode::HardLink,
            reused: true,
        });
    }
    if cached_paths.len() != files.len() {
        bail!(
            "Bundle cache path count mismatch: expected {}, got {}",
            files.len(),
            cached_paths.len()
        );
    }

    cleanup_incomplete_bundle(models_dir, directory_name)?;
    if is_cancelled() {
        return Ok(BundlePrepareOutcome::Cancelled);
    }

    let mut cached_sources = Vec::with_capacity(cached_paths.len());
    for (file, cached_path) in files.iter().zip(cached_paths) {
        if is_cancelled() {
            return Ok(BundlePrepareOutcome::Cancelled);
        }
        verify_cached_file(cached_path, file)?;
        cached_sources.push(fs::canonicalize(cached_path).with_context(|| {
            format!(
                "Failed to resolve cached bundle file {}",
                cached_path.display()
            )
        })?);
    }

    if is_cancelled() {
        return Ok(BundlePrepareOutcome::Cancelled);
    }
    if paths.final_dir.exists() {
        remove_owned_path(&paths.final_dir)?;
    }
    fs::create_dir_all(&paths.staging_dir).with_context(|| {
        format!(
            "Failed to create bundle staging directory {}",
            paths.staging_dir.display()
        )
    })?;
    let mut staging_guard = StagingGuard {
        path: paths.staging_dir.clone(),
        armed: true,
    };

    let mut hard_links = 0usize;
    let mut copies = 0usize;
    for (file, cached_path) in files.iter().zip(&cached_sources) {
        if is_cancelled() {
            return Ok(BundlePrepareOutcome::Cancelled);
        }

        let destination = paths.staging_dir.join(&file.local_filename);
        match (materializers.linker)(cached_path, &destination) {
            Ok(()) => hard_links += 1,
            Err(_) => {
                (materializers.copier)(cached_path, &destination).with_context(|| {
                    format!(
                        "Failed to copy bundle file {} to {}",
                        cached_path.display(),
                        destination.display()
                    )
                })?;
                copies += 1;
            }
        }

        let destination_size = fs::metadata(&destination)
            .with_context(|| {
                format!(
                    "Failed to inspect materialized bundle file {}",
                    destination.display()
                )
            })?
            .len();
        if destination_size != file.size_bytes {
            bail!(
                "Materialized bundle size mismatch for {}: expected {}, got {}",
                file.local_filename,
                file.size_bytes,
                destination_size
            );
        }
    }

    if is_cancelled() {
        return Ok(BundlePrepareOutcome::Cancelled);
    }

    fs::rename(&paths.staging_dir, &paths.final_dir).with_context(|| {
        format!(
            "Failed to atomically publish bundle {}",
            paths.final_dir.display()
        )
    })?;
    staging_guard.armed = false;

    if !bundle_is_complete(&paths.final_dir, files) {
        let _ = remove_owned_path(&paths.final_dir);
        bail!("Published bundle failed final layout verification");
    }

    progress.mark_ready();
    let materialization = match (hard_links > 0, copies > 0) {
        (true, false) => MaterializationMode::HardLink,
        (false, true) => MaterializationMode::Copy,
        (true, true) => MaterializationMode::Mixed,
        (false, false) => MaterializationMode::Copy,
    };
    Ok(BundlePrepareOutcome::Ready {
        materialization,
        reused: false,
    })
}

#[cfg(test)]
mod tests {
    use super::{
        bundle_is_complete, bundle_paths, cleanup_incomplete_bundle, completed_bundle_path,
        delete_bundle, prepare_bundle_from_cache, prepare_bundle_from_cache_with_linker,
        prepare_bundle_from_cache_with_materializers, resolve_cached_files, validate_bundle,
        verify_cached_file_with_cleanup, BundleMaterializers, BundlePrepareOutcome,
        BundleProgressSnapshot, BundleProgressTracker, MaterializationMode,
    };
    use crate::managers::model::{HuggingFaceBundleFile, ModelSource};
    use sha2::{Digest, Sha256};
    use std::collections::{HashMap, HashSet};
    use std::env;
    use std::fs;
    use std::io;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};
    use std::time::Instant;
    use tempfile::TempDir;

    const REVISION: &str = "458860e1983aef670dd9795fb6af603c82767d5d";
    const MODEL_SHA256: &str = "e08e27ae5669b39f0c378fae101bbbb9a80505f74f9b66719c309bf5b894a480";
    const VOCAB_SHA256: &str = "4d130287892e1099fedfb3f93c4b4cf8a263151158801680b28977d1be4133f4";

    fn normalize_gigaam_text(text: &str) -> String {
        const LETTERS: &str =
            "abcdefghijklmnopqrstuvwxyzабвгдежзийклмнопрстуфхцчшщъыьэюяёіғқңүұһәө";
        let mut normalized = String::with_capacity(text.len());

        for character in text.to_lowercase().chars() {
            if LETTERS.contains(character) || character == '\'' {
                normalized.push(character);
            } else if matches!(character, '’' | 'ʻ' | 'ʼ' | '`') {
                normalized.push('\'');
            } else {
                normalized.push(' ');
            }
        }

        normalized.split_whitespace().collect::<Vec<_>>().join(" ")
    }

    fn word_error_rate(reference: &str, hypothesis: &str) -> f64 {
        let reference: Vec<_> = reference.split_whitespace().collect();
        let hypothesis: Vec<_> = hypothesis.split_whitespace().collect();
        if reference.is_empty() {
            return f64::from(!hypothesis.is_empty());
        }

        let mut previous: Vec<usize> = (0..=hypothesis.len()).collect();
        for (reference_index, reference_word) in reference.iter().enumerate() {
            let mut current = vec![reference_index + 1; hypothesis.len() + 1];
            for (hypothesis_index, hypothesis_word) in hypothesis.iter().enumerate() {
                let substitution =
                    previous[hypothesis_index] + usize::from(reference_word != hypothesis_word);
                let insertion = current[hypothesis_index] + 1;
                let deletion = previous[hypothesis_index + 1] + 1;
                current[hypothesis_index + 1] = substitution.min(insertion).min(deletion);
            }
            previous = current;
        }

        previous[hypothesis.len()] as f64 / reference.len() as f64
    }

    fn word_overlap(reference: &str, hypothesis: &str) -> usize {
        let mut remaining = HashMap::new();
        for word in reference.split_whitespace() {
            *remaining.entry(word).or_insert(0usize) += 1;
        }

        hypothesis
            .split_whitespace()
            .filter(|word| {
                let Some(count) = remaining.get_mut(word) else {
                    return false;
                };
                if *count == 0 {
                    return false;
                }
                *count -= 1;
                true
            })
            .count()
    }

    #[derive(serde::Deserialize)]
    struct GigaAMFixture {
        language: String,
        wav_path: PathBuf,
        reference: String,
    }

    fn read_fixture_wav(path: &Path) -> (Vec<f32>, f64) {
        let mut reader = hound::WavReader::open(path).expect("fixture WAV must open");
        let spec = reader.spec();
        assert_eq!(
            spec.channels,
            1,
            "fixture WAV must be mono: {}",
            path.display()
        );
        assert_eq!(
            spec.sample_rate,
            16_000,
            "fixture WAV must be 16 kHz: {}",
            path.display()
        );
        let samples: Vec<f32> = match (spec.sample_format, spec.bits_per_sample) {
            (hound::SampleFormat::Int, 16) => reader
                .samples::<i16>()
                .map(|sample| sample.expect("fixture WAV sample must decode") as f32 / 32768.0)
                .collect(),
            (hound::SampleFormat::Float, 32) => reader
                .samples::<f32>()
                .map(|sample| sample.expect("fixture WAV sample must decode"))
                .collect(),
            format => panic!(
                "fixture WAV must be 16-bit PCM or float32, got {format:?}: {}",
                path.display()
            ),
        };
        let duration = samples.len() as f64 / f64::from(spec.sample_rate);
        (samples, duration)
    }

    fn valid_files() -> Vec<HuggingFaceBundleFile> {
        vec![
            HuggingFaceBundleFile {
                remote_filename: "multilingual_ctc.int8.onnx".into(),
                local_filename: "model.int8.onnx".into(),
                size_bytes: 224_762_204,
                sha256: MODEL_SHA256.into(),
            },
            HuggingFaceBundleFile {
                remote_filename: "multilingual_vocab.txt".into(),
                local_filename: "vocab.txt".into(),
                size_bytes: 393,
                sha256: VOCAB_SHA256.into(),
            },
        ]
    }

    fn sha256(data: &[u8]) -> String {
        format!("{:x}", Sha256::digest(data))
    }

    fn local_fixture() -> (TempDir, PathBuf, Vec<HuggingFaceBundleFile>, Vec<PathBuf>) {
        let temp = TempDir::new().unwrap();
        let models_dir = temp.path().join("models");
        let cache_dir = temp.path().join("cache");
        fs::create_dir_all(&models_dir).unwrap();
        fs::create_dir_all(&cache_dir).unwrap();

        let model_bytes = b"small model fixture";
        let vocab_bytes = b"a\nb\nc\n";
        let cached_paths = vec![cache_dir.join("model"), cache_dir.join("vocab")];
        fs::write(&cached_paths[0], model_bytes).unwrap();
        fs::write(&cached_paths[1], vocab_bytes).unwrap();

        let files = vec![
            HuggingFaceBundleFile {
                remote_filename: "remote-model.onnx".into(),
                local_filename: "model.int8.onnx".into(),
                size_bytes: model_bytes.len() as u64,
                sha256: sha256(model_bytes),
            },
            HuggingFaceBundleFile {
                remote_filename: "remote-vocab.txt".into(),
                local_filename: "vocab.txt".into(),
                size_bytes: vocab_bytes.len() as u64,
                sha256: sha256(vocab_bytes),
            },
        ];

        (temp, models_dir, files, cached_paths)
    }

    fn recording_progress(
        total: u64,
    ) -> (
        BundleProgressTracker,
        Arc<Mutex<Vec<BundleProgressSnapshot>>>,
    ) {
        let snapshots = Arc::new(Mutex::new(Vec::new()));
        let recorded = Arc::clone(&snapshots);
        let tracker = BundleProgressTracker::new(
            total,
            Arc::new(move |snapshot| recorded.lock().unwrap().push(snapshot)),
        );
        (tracker, snapshots)
    }

    fn assert_invalid(files: &[HuggingFaceBundleFile], expected: &str) {
        let error = validate_bundle("istupakov/gigaam-multilingual-ctc-onnx", REVISION, files)
            .expect_err("bundle must be rejected");
        assert!(
            error.to_string().contains(expected),
            "expected error containing {expected:?}, got {error:#}"
        );
    }

    #[test]
    fn accepts_model_and_vocab_bundle() {
        validate_bundle(
            "istupakov/gigaam-multilingual-ctc-onnx",
            REVISION,
            &valid_files(),
        )
        .unwrap();
    }

    #[test]
    fn rejects_empty_bundle() {
        assert_invalid(&[], "at least one file");
    }

    #[test]
    fn rejects_empty_repo_id() {
        let error = validate_bundle("", REVISION, &valid_files()).unwrap_err();
        assert!(error.to_string().contains("repo id"));
    }

    #[test]
    fn rejects_empty_revision() {
        let error = validate_bundle("istupakov/gigaam-multilingual-ctc-onnx", "", &valid_files())
            .unwrap_err();
        assert!(error.to_string().contains("revision"));
    }

    #[test]
    fn rejects_mutable_revision() {
        let error = validate_bundle(
            "istupakov/gigaam-multilingual-ctc-onnx",
            "main",
            &valid_files(),
        )
        .unwrap_err();
        assert!(error.to_string().contains("40-character commit"));
    }

    #[test]
    fn rejects_empty_remote_filename() {
        let mut files = valid_files();
        files[0].remote_filename.clear();
        assert_invalid(&files, "remote filename");
    }

    #[test]
    fn rejects_empty_local_filename() {
        let mut files = valid_files();
        files[0].local_filename.clear();
        assert_invalid(&files, "local filename");
    }

    #[test]
    fn rejects_absolute_local_filename() {
        let mut files = valid_files();
        files[0].local_filename = "/tmp/model.onnx".into();
        assert_invalid(&files, "single path component");
    }

    #[test]
    fn rejects_traversal_local_filename() {
        let mut files = valid_files();
        files[0].local_filename = "../model.onnx".into();
        assert_invalid(&files, "single path component");
    }

    #[test]
    fn rejects_local_path_separator() {
        for filename in ["nested/model.onnx", "nested\\model.onnx"] {
            let mut files = valid_files();
            files[0].local_filename = filename.into();
            assert_invalid(&files, "single path component");
        }
    }

    #[test]
    fn rejects_duplicate_local_filename() {
        let mut files = valid_files();
        files[1].local_filename = files[0].local_filename.clone();
        assert_invalid(&files, "duplicate local filename");
    }

    #[test]
    fn rejects_zero_size() {
        let mut files = valid_files();
        files[0].size_bytes = 0;
        assert_invalid(&files, "positive size");
    }

    #[test]
    fn rejects_malformed_sha256() {
        for sha256 in ["", "abc", &"g".repeat(64), &"0".repeat(63)] {
            let mut files = valid_files();
            files[0].sha256 = sha256.into();
            assert_invalid(&files, "64 hexadecimal");
        }
    }

    #[test]
    fn builds_deterministic_final_and_staging_paths() {
        let root = Path::new("models-root");
        let paths = bundle_paths(root, "gigaam-multilingual-220m-int8");

        assert_eq!(paths.final_dir, root.join("gigaam-multilingual-220m-int8"));
        assert_eq!(
            paths.staging_dir,
            root.join("gigaam-multilingual-220m-int8.staging")
        );
    }

    #[test]
    fn bundle_source_serialization_round_trip_preserves_contract() {
        let source = ModelSource::HuggingFaceBundle {
            repo_id: "istupakov/gigaam-multilingual-ctc-onnx".into(),
            revision: REVISION.into(),
            files: valid_files(),
        };

        let json = serde_json::to_string(&source).unwrap();
        assert!(json.contains(REVISION));
        assert!(json.contains("multilingual_ctc.int8.onnx"));
        assert!(json.contains("model.int8.onnx"));
        assert!(!json.to_lowercase().contains("token"));

        let decoded: ModelSource = serde_json::from_str(&json).unwrap();
        match decoded {
            ModelSource::HuggingFaceBundle {
                repo_id,
                revision,
                files,
            } => {
                assert_eq!(repo_id, "istupakov/gigaam-multilingual-ctc-onnx");
                assert_eq!(revision, REVISION);
                assert_eq!(files.len(), 2);
                assert_eq!(files[0].size_bytes, 224_762_204);
                assert_eq!(files[1].local_filename, "vocab.txt");
            }
            _ => panic!("bundle source variant was not preserved"),
        }
    }

    #[test]
    fn existing_source_variants_still_round_trip() {
        let sources = [
            ModelSource::Url {
                url: "https://example.com/model.bin".into(),
                sha256: Some("0".repeat(64)),
            },
            ModelSource::HuggingFace {
                repo_id: "owner/repo".into(),
                revision: "main".into(),
            },
            ModelSource::Local,
        ];

        for source in sources {
            let json = serde_json::to_string(&source).unwrap();
            let decoded: ModelSource = serde_json::from_str(&json).unwrap();
            assert_eq!(
                std::mem::discriminant(&source),
                std::mem::discriminant(&decoded)
            );
        }
    }

    #[test]
    fn aggregate_progress_is_monotonic_and_reaches_100_only_when_ready() {
        let (tracker, snapshots) = recording_progress(10);
        tracker.complete_cached(3);
        tracker.begin_file(7);
        tracker.advance_file(2);
        tracker.advance_file(5);
        tracker.finish_file();

        let before_ready = snapshots.lock().unwrap().clone();
        assert!(before_ready
            .iter()
            .all(|snapshot| snapshot.percentage < 100.0));
        assert!(before_ready
            .windows(2)
            .all(|pair| pair[0].downloaded <= pair[1].downloaded));

        tracker.mark_ready();
        let after_ready = snapshots.lock().unwrap();
        assert_eq!(after_ready.last().unwrap().downloaded, 10);
        assert_eq!(after_ready.last().unwrap().total, 10);
        assert_eq!(after_ready.last().unwrap().percentage, 100.0);
        assert!(after_ready
            .windows(2)
            .all(|pair| pair[0].percentage <= pair[1].percentage));
    }

    #[test]
    fn large_fp32_total_and_progress_preserve_u64_bytes() {
        let files = [
            HuggingFaceBundleFile {
                remote_filename: "multilingual_large_ctc.onnx".into(),
                local_filename: "model.onnx".into(),
                size_bytes: 909_828,
                sha256: "4a2d22279e90648262e1259e82982f1f1f7e2c4957e187c2b68459458c92fd5f".into(),
            },
            HuggingFaceBundleFile {
                remote_filename: "multilingual_large_ctc.onnx.data".into(),
                local_filename: "multilingual_large_ctc.onnx.data".into(),
                size_bytes: 2_343_837_696,
                sha256: "5a7bf60fd3883a707dda19862b58a9a30777bde3e439ff76b49580da1f18b1f1".into(),
            },
            HuggingFaceBundleFile {
                remote_filename: "multilingual_vocab.txt".into(),
                local_filename: "vocab.txt".into(),
                size_bytes: 393,
                sha256: VOCAB_SHA256.into(),
            },
        ];
        validate_bundle(
            "istupakov/gigaam-multilingual-large-ctc-onnx",
            "07665ab5e54371dd1ac7b8b10f06478003723573",
            &files,
        )
        .unwrap();

        let total = files.iter().map(|file| file.size_bytes).sum::<u64>();
        assert_eq!(total, 2_344_747_917);
        assert!(total > u64::from(u32::MAX) / 2);

        let (tracker, snapshots) = recording_progress(total);
        for file in &files {
            tracker.complete_cached(file.size_bytes);
        }
        assert_eq!(snapshots.lock().unwrap().last().unwrap().downloaded, total);
        assert!(snapshots.lock().unwrap().last().unwrap().percentage < 100.0);
        tracker.mark_ready();
        let final_snapshot = *snapshots.lock().unwrap().last().unwrap();
        assert_eq!(final_snapshot.total, 2_344_747_917);
        assert_eq!(final_snapshot.downloaded, 2_344_747_917);
        assert_eq!(final_snapshot.percentage, 100.0);
    }

    #[test]
    fn int8_loader_resolution_falls_back_to_fp32_model() {
        let model_dir = TempDir::new().unwrap();
        fs::write(model_dir.path().join("model.onnx"), b"fp32 fixture").unwrap();

        let resolved = transcribe_rs::onnx::session::resolve_model_path(
            model_dir.path(),
            "model",
            &transcribe_rs::onnx::Quantization::Int8,
        );

        assert_eq!(resolved, model_dir.path().join("model.onnx"));
    }

    #[test]
    fn cached_files_are_resolved_without_missing_downloads() {
        let (_temp, _models_dir, files, cached_paths) = local_fixture();
        let mut lookup_count = 0;
        let resolved = resolve_cached_files(&files, |remote_filename| {
            lookup_count += 1;
            files
                .iter()
                .position(|file| file.remote_filename == remote_filename)
                .map(|index| cached_paths[index].clone())
        });

        assert_eq!(lookup_count, 2);
        assert!(resolved.iter().all(Option::is_some));
    }

    #[test]
    fn materializes_exact_bundle_atomically() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, snapshots) = recording_progress(total);

        let outcome = prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap();

        assert_eq!(
            outcome,
            BundlePrepareOutcome::Ready {
                materialization: MaterializationMode::HardLink,
                reused: false,
            }
        );
        let paths = bundle_paths(&models_dir, "bundle");
        assert!(bundle_is_complete(&paths.final_dir, &files));
        assert!(!paths.staging_dir.exists());
        let mut names: Vec<_> = fs::read_dir(&paths.final_dir)
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect();
        names.sort();
        assert_eq!(names, ["model.int8.onnx", "vocab.txt"]);
        assert_eq!(snapshots.lock().unwrap().last().unwrap().percentage, 100.0);
    }

    #[test]
    fn complete_bundle_is_reused_without_materialization() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);
        prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap();

        let link_calls = Arc::new(Mutex::new(0));
        let calls = Arc::clone(&link_calls);
        let (second_progress, _) = recording_progress(total);
        let outcome = prepare_bundle_from_cache_with_linker(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &second_progress,
            move |_, _| {
                *calls.lock().unwrap() += 1;
                Err(io::Error::other("materialization must be skipped"))
            },
        )
        .unwrap();

        assert_eq!(
            outcome,
            BundlePrepareOutcome::Ready {
                materialization: MaterializationMode::HardLink,
                reused: true,
            }
        );
        assert_eq!(*link_calls.lock().unwrap(), 0);
    }

    #[test]
    fn hard_link_failure_falls_back_to_copy() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);
        let outcome = prepare_bundle_from_cache_with_linker(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
            |_, _| Err(io::Error::other("forced cross-filesystem link failure")),
        )
        .unwrap();

        assert_eq!(
            outcome,
            BundlePrepareOutcome::Ready {
                materialization: MaterializationMode::Copy,
                reused: false,
            }
        );
        assert_eq!(
            fs::read(models_dir.join("bundle/model.int8.onnx")).unwrap(),
            b"small model fixture"
        );
    }

    #[test]
    fn copy_failure_leaves_bundle_unavailable_and_cleans_staging() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);
        let error = prepare_bundle_from_cache_with_materializers(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
            BundleMaterializers {
                linker: |_: &Path, _: &Path| {
                    Err(io::Error::other("forced cross-filesystem link failure"))
                },
                copier: |_: &Path, _: &Path| Err(io::Error::other("forced disk full")),
            },
        )
        .unwrap_err();

        let paths = bundle_paths(&models_dir, "bundle");
        assert!(!bundle_is_complete(&paths.final_dir, &files));
        assert!(!paths.final_dir.exists());
        assert!(!paths.staging_dir.exists());
        assert!(format!("{error:#}").contains("Failed to copy bundle file"));
        assert!(format!("{error:#}").contains("forced disk full"));
    }

    #[test]
    fn cancellation_after_final_materialization_prevents_publish() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);
        let cancelled = Arc::new(AtomicBool::new(false));
        let checked_cancelled = Arc::clone(&cancelled);
        let link_count = Arc::new(AtomicUsize::new(0));
        let counted_links = Arc::clone(&link_count);
        let set_cancelled = Arc::clone(&cancelled);
        let file_count = files.len();

        let outcome = prepare_bundle_from_cache_with_materializers(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &move || checked_cancelled.load(Ordering::SeqCst),
            &progress,
            BundleMaterializers {
                linker: move |source: &Path, destination: &Path| {
                    fs::hard_link(source, destination)?;
                    if counted_links.fetch_add(1, Ordering::SeqCst) + 1 == file_count {
                        set_cancelled.store(true, Ordering::SeqCst);
                    }
                    Ok(())
                },
                copier: |source: &Path, destination: &Path| fs::copy(source, destination),
            },
        )
        .unwrap();

        let paths = bundle_paths(&models_dir, "bundle");
        assert_eq!(outcome, BundlePrepareOutcome::Cancelled);
        assert!(!paths.final_dir.exists());
        assert!(!paths.staging_dir.exists());
    }

    #[test]
    fn staging_directory_write_failure_leaves_bundle_unavailable() {
        let (temp, _models_dir, files, cached_paths) = local_fixture();
        let models_file = temp.path().join("models-file");
        fs::write(&models_file, b"not a directory").unwrap();
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);
        let error = prepare_bundle_from_cache(
            &models_file,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap_err();

        let paths = bundle_paths(&models_file, "bundle");
        assert!(!bundle_is_complete(&paths.final_dir, &files));
        assert!(!paths.final_dir.exists());
        assert!(!paths.staging_dir.exists());
        assert!(error
            .to_string()
            .contains("Failed to create bundle staging directory"));
    }

    #[cfg(unix)]
    #[test]
    fn hugging_face_relative_symlink_materializes_target_file() {
        use std::os::unix::fs::symlink;

        let (temp, models_dir, files, mut cached_paths) = local_fixture();
        let cache_root = temp.path().join("models--owner--repo");
        let blob = cache_root.join("blobs/model");
        let snapshot = cache_root.join("snapshots/revision");
        fs::create_dir_all(blob.parent().unwrap()).unwrap();
        fs::create_dir_all(&snapshot).unwrap();
        fs::write(&blob, b"small model fixture").unwrap();
        let cached_symlink = snapshot.join("model.onnx");
        symlink("../../blobs/model", &cached_symlink).unwrap();
        cached_paths[0] = cached_symlink;

        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);
        prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap();

        let materialized = models_dir.join("bundle/model.int8.onnx");
        assert!(!fs::symlink_metadata(&materialized)
            .unwrap()
            .file_type()
            .is_symlink());
        assert_eq!(fs::read(materialized).unwrap(), b"small model fixture");
    }

    #[test]
    fn cancellation_preserves_cache_and_removes_owned_staging_for_all_variants() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        let total = files.iter().map(|file| file.size_bytes).sum();
        for id in [
            "gigaam-multilingual-220m-int8",
            "gigaam-multilingual-220m-fp32-cuda",
            "gigaam-multilingual-600m-int8",
            "gigaam-multilingual-600m-fp32-cuda",
        ] {
            let paths = bundle_paths(&models_dir, id);
            fs::create_dir_all(&paths.staging_dir).unwrap();
            fs::write(paths.staging_dir.join("orphan"), b"partial").unwrap();
            let (progress, _) = recording_progress(total);

            let outcome = prepare_bundle_from_cache(
                &models_dir,
                id,
                &files,
                &cached_paths,
                &|| true,
                &progress,
            )
            .unwrap();

            assert_eq!(outcome, BundlePrepareOutcome::Cancelled);
            assert!(!paths.final_dir.exists());
            assert!(!paths.staging_dir.exists());
            assert!(cached_paths.iter().all(|path| path.exists()));
        }
    }

    #[test]
    fn size_failure_removes_corrupt_cache_and_retry_succeeds() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        fs::write(&cached_paths[0], b"short").unwrap();
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);

        let error = prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap_err();
        assert!(error.to_string().contains("size mismatch"));
        assert!(!cached_paths[0].exists());
        assert!(!models_dir.join("bundle").exists());

        fs::write(&cached_paths[0], b"small model fixture").unwrap();
        let (retry_progress, _) = recording_progress(total);
        let retry = prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &retry_progress,
        )
        .unwrap();
        assert!(matches!(retry, BundlePrepareOutcome::Ready { .. }));
    }

    #[test]
    fn checksum_failure_removes_corrupt_cache_and_final_state() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        fs::write(&cached_paths[0], b"corrupt model bytes").unwrap();
        assert_eq!(
            fs::metadata(&cached_paths[0]).unwrap().len(),
            files[0].size_bytes
        );
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);

        let error = prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap_err();
        assert!(error.to_string().contains("SHA256 mismatch"));
        assert!(!cached_paths[0].exists());
        assert!(!models_dir.join("bundle").exists());
        assert!(!models_dir.join("bundle.staging").exists());
    }

    #[test]
    fn checksum_failure_removes_hugging_face_repo_cache_root() {
        let (temp, models_dir, files, mut cached_paths) = local_fixture();
        let repo_root = temp.path().join("models--owner--repo");
        let snapshot = repo_root.join("snapshots/commit");
        fs::create_dir_all(&snapshot).unwrap();
        cached_paths[0] = snapshot.join("model.onnx");
        fs::write(&cached_paths[0], b"corrupt model bytes").unwrap();
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);

        let error = prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap_err();

        assert!(error.to_string().contains("SHA256 mismatch"));
        assert!(!repo_root.exists());
    }

    #[test]
    fn corrupt_cache_cleanup_failure_preserves_both_error_contexts() {
        let (_temp, _models_dir, files, cached_paths) = local_fixture();
        fs::write(&cached_paths[0], b"corrupt model bytes").unwrap();

        let error = verify_cached_file_with_cleanup(&cached_paths[0], &files[0], |_| {
            Err(anyhow::anyhow!("forced permission denied"))
        })
        .unwrap_err();
        let chain = format!("{error:#}");

        assert!(chain.contains("SHA256 mismatch"));
        assert!(chain.contains("Failed to clear corrupt cache state"));
        assert!(chain.contains("forced permission denied"));
    }

    #[test]
    fn incomplete_final_directory_is_replaced_by_exact_bundle() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        let paths = bundle_paths(&models_dir, "bundle");
        fs::create_dir_all(&paths.final_dir).unwrap();
        fs::write(paths.final_dir.join("unexpected"), b"stale").unwrap();
        assert!(!bundle_is_complete(&paths.final_dir, &files));

        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);
        prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap();

        assert!(bundle_is_complete(&paths.final_dir, &files));
        assert!(!paths.final_dir.join("unexpected").exists());
    }

    #[test]
    fn restart_cleanup_and_delete_remove_only_owned_bundle_paths() {
        let (temp, models_dir, _files, _cached_paths) = local_fixture();
        let paths = bundle_paths(&models_dir, "bundle");
        fs::create_dir_all(&paths.final_dir).unwrap();
        fs::create_dir_all(&paths.staging_dir).unwrap();
        let unrelated = temp.path().join("keep-me");
        fs::write(&unrelated, b"keep").unwrap();

        cleanup_incomplete_bundle(&models_dir, "bundle").unwrap();
        assert!(!paths.staging_dir.exists());
        assert!(paths.final_dir.exists());

        assert!(delete_bundle(&models_dir, "bundle").unwrap());
        assert!(!paths.final_dir.exists());
        assert!(unrelated.exists());
    }

    #[test]
    fn completed_bundle_path_rejects_incomplete_and_returns_exact_final_dir() {
        let (_temp, models_dir, files, cached_paths) = local_fixture();
        let error = completed_bundle_path(&models_dir, "bundle", &files).unwrap_err();
        assert!(error
            .to_string()
            .contains("Complete model bundle not found"));

        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, _) = recording_progress(total);
        prepare_bundle_from_cache(
            &models_dir,
            "bundle",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .unwrap();

        assert_eq!(
            completed_bundle_path(&models_dir, "bundle", &files).unwrap(),
            models_dir.join("bundle")
        );
    }

    #[test]
    fn gigaam_evaluation_helpers_are_deterministic() {
        assert_eq!(
            normalize_gigaam_text("  OʻZBEK—ТЕСТ! 2026  "),
            "o'zbek тест"
        );
        assert_eq!(word_error_rate("one two three", "one two three"), 0.0);
        assert_eq!(
            word_error_rate("one two three", "one four three"),
            1.0 / 3.0
        );
        assert_eq!(word_error_rate("one two", "one two extra"), 0.5);
        assert_eq!(word_error_rate("", ""), 0.0);
        assert_eq!(word_error_rate("", "extra"), 1.0);
        assert_eq!(word_overlap("bir ikki ikki uch", "ikki uch uch"), 2);
    }

    #[test]
    #[ignore = "requires HANDY_GIGAAM_FIXTURES and downloads pinned model files"]
    fn gigaam_multilingual_real_audio() {
        let Some(manifest_path) = env::var_os("HANDY_GIGAAM_FIXTURES").map(PathBuf::from) else {
            println!(
                "SKIP gigaam_multilingual_real_audio: HANDY_GIGAAM_FIXTURES is not set; no network access"
            );
            return;
        };

        let fixtures: Vec<GigaAMFixture> = serde_json::from_slice(
            &fs::read(&manifest_path).expect("fixture manifest must be readable"),
        )
        .expect("fixture manifest must be valid JSON");
        let languages: HashSet<_> = fixtures
            .iter()
            .map(|fixture| fixture.language.as_str())
            .collect();
        assert_eq!(
            languages,
            HashSet::from(["en_us", "ru_ru", "kk_kz", "ky_kg", "uz_uz"]),
            "fixture manifest must contain exactly one supported locale each"
        );
        assert_eq!(
            fixtures.len(),
            languages.len(),
            "fixture locales must be unique"
        );

        let files = valid_files();
        validate_bundle("istupakov/gigaam-multilingual-ctc-onnx", REVISION, &files).unwrap();

        let api = hf_hub::api::sync::ApiBuilder::new()
            .with_progress(false)
            .build()
            .expect("Hugging Face API must initialize");
        let repo = api.repo(hf_hub::Repo::with_revision(
            "istupakov/gigaam-multilingual-ctc-onnx".to_string(),
            hf_hub::RepoType::Model,
            REVISION.to_string(),
        ));
        let cached_paths: Vec<_> = files
            .iter()
            .map(|file| {
                repo.get(&file.remote_filename).unwrap_or_else(|error| {
                    panic!("failed to fetch {}: {error}", file.remote_filename)
                })
            })
            .collect();

        let model_root = TempDir::new().expect("fresh model root must be created");
        let total = files.iter().map(|file| file.size_bytes).sum();
        let (progress, snapshots) = recording_progress(total);
        let outcome = prepare_bundle_from_cache(
            model_root.path(),
            "gigaam-multilingual-220m-int8",
            &files,
            &cached_paths,
            &|| false,
            &progress,
        )
        .expect("pinned bundle must verify and materialize");
        let model_dir =
            completed_bundle_path(model_root.path(), "gigaam-multilingual-220m-int8", &files)
                .expect("materialized bundle must be complete");

        println!(
            "revision={REVISION} bundle={outcome:?} path={}",
            model_dir.display()
        );
        for file in &files {
            println!(
                "checksum={} bytes={} sha256={} status=ok",
                file.remote_filename, file.size_bytes, file.sha256
            );
        }
        let final_bytes: u64 = files
            .iter()
            .map(|file| {
                fs::metadata(model_dir.join(&file.local_filename))
                    .unwrap()
                    .len()
            })
            .sum();
        let max_progress = snapshots
            .lock()
            .unwrap()
            .iter()
            .map(|snapshot| snapshot.percentage)
            .fold(0.0, f64::max);
        println!(
            "source_bytes={total} final_materialized_bytes={final_bytes} max_progress={max_progress:.1}"
        );

        transcribe_rs::set_ort_accelerator(transcribe_rs::OrtAccelerator::CpuOnly);
        let load_started = Instant::now();
        let mut model = transcribe_rs::onnx::gigaam::GigaAMModel::load(
            &model_dir,
            &transcribe_rs::onnx::Quantization::Int8,
        )
        .expect("materialized GigaAM bundle must load");
        println!(
            "model_load_seconds={:.3}",
            load_started.elapsed().as_secs_f64()
        );
        use transcribe_rs::SpeechModel;

        let mut long_audio = Vec::new();
        let mut uzbek_overlap = None;
        for fixture in &fixtures {
            assert!(
                !fixture
                    .reference
                    .chars()
                    .any(|character| character.is_ascii_digit()),
                "fixture reference must be digit-free: {}",
                fixture.language
            );
            let normalized_reference = normalize_gigaam_text(&fixture.reference);
            assert!(!normalized_reference.is_empty());
            let (samples, audio_seconds) = read_fixture_wav(&fixture.wav_path);
            assert!(
                audio_seconds <= 30.0,
                "fixture exceeds 30 seconds: {} ({audio_seconds:.3})",
                fixture.language
            );
            long_audio.extend_from_slice(&samples);

            let started = Instant::now();
            let result = model
                .transcribe(&samples, &transcribe_rs::TranscribeOptions::default())
                .unwrap_or_else(|error| panic!("{} inference failed: {error}", fixture.language));
            let inference_seconds = started.elapsed().as_secs_f64();
            let normalized_hypothesis = normalize_gigaam_text(&result.text);
            assert!(
                !normalized_hypothesis.is_empty(),
                "{} hypothesis must not be empty",
                fixture.language
            );
            assert_eq!(
                result.text.trim(),
                normalized_hypothesis,
                "{} hypothesis must use only GigaAM vocabulary text",
                fixture.language
            );
            let wer = word_error_rate(&normalized_reference, &normalized_hypothesis);
            let overlap = word_overlap(&normalized_reference, &normalized_hypothesis);
            let rtf = inference_seconds / audio_seconds;
            println!(
                "language={} audio_seconds={audio_seconds:.3} inference_seconds={inference_seconds:.3} cpu_rtf={rtf:.3} wer={wer:.3} overlap={overlap}",
                fixture.language
            );
            println!("reference={normalized_reference}");
            println!("hypothesis={normalized_hypothesis}");
            assert!(
                wer <= 0.50,
                "{} WER {wer:.3} exceeds 0.50",
                fixture.language
            );
            if fixture.language == "uz_uz" {
                uzbek_overlap = Some(overlap);
            }
        }

        let uzbek_overlap = uzbek_overlap.expect("Uzbek fixture must be present");
        assert!(
            uzbek_overlap >= 5,
            "Uzbek reference-word overlap {uzbek_overlap} is below 5"
        );
        println!("uzbek_overlap={uzbek_overlap}");

        const LONG_AUDIO_SAMPLES: usize = 31 * 16_000;
        let base_audio = long_audio.clone();
        while long_audio.len() < LONG_AUDIO_SAMPLES {
            long_audio.extend_from_slice(&base_audio);
        }
        long_audio.truncate(LONG_AUDIO_SAMPLES);
        let long_seconds = long_audio.len() as f64 / 16_000.0;
        let started = Instant::now();
        let result = model
            .transcribe(&long_audio, &transcribe_rs::TranscribeOptions::default())
            .expect("over-30-second GigaAM inference must complete");
        let inference_seconds = started.elapsed().as_secs_f64();
        let rtf = inference_seconds / long_seconds;
        println!(
            "long_audio_seconds={long_seconds:.3} inference_seconds={inference_seconds:.3} cpu_rtf={rtf:.3} hypothesis_chars={} status=completed",
            result.text.chars().count()
        );
    }
}
