import AST
import Foundation
import Testing

@testable import Rego
@testable import SDK

@Suite
struct TarballBundleLoaderTests {
    // TODO: Finish porting the testGetTarballFile helper function.
    // TODO: Create Tarball writer helpers, so that we can implement these tests.
}

// Usage:
//   let tempDir = try createTempDirectory()
//   defer { try? FileManager.default.removeItem(at: tempDir) }
func createTempDirectory() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    return tempDir
}

// ----------------------------------------------------------------------------
// Tests ported over from: v1/bundle/file_test.go

// func TestTarballLoader(t *testing.T) {

// 	files := map[string]string{
// 		"/archive.tar.gz": "",
// 	}

// 	test.WithTempFS(files, func(rootDir string) {
// 		tarballFile := filepath.Join(rootDir, "archive.tar.gz")
// 		f := testGetTarballFile(t, rootDir)

// 		loader := NewTarballLoaderWithBaseURL(f, tarballFile)

// 		defer f.Close()

// 		testLoader(t, loader, tarballFile, archiveFiles)
// 	})
// }

// func TestTarballLoaderWithMaxSizeBytesLimit(t *testing.T) {
// 	rootDir := t.TempDir()
// 	tarballFile := filepath.Join(rootDir, "archive.tar.gz")

// 	f := testGetTarballFile(t, rootDir)

// 	loader := NewTarballLoaderWithBaseURL(f, tarballFile).WithSizeLimitBytes(5)

// 	defer f.Close()

// 	_, err := loader.NextFile()
// 	if err == nil {
// 		t.Fatal("Expected error but got nil")
// 	}

// 	// Order of iteration over files in the tarball aren't necessarily in a deterministic order,
// 	// but luckily we have 2 files of 18 bytes. Just skip checking for the name here.
// 	expected := "size (18 bytes) exceeds configured size_limit_bytes (5 bytes)"

// 	if !strings.Contains(err.Error(), expected) {
// 		t.Errorf("Expected %q but got %v", expected, err)
// 	}
// }
// func TestTarballLoaderWithFilter(t *testing.T) {

// 	files := map[string]string{
// 		"/a/data.json":            `{"foo": "not-bar"}`,
// 		"/policy.rego":            "package foo\n p = 1",
// 		"/policy_test.rego":       "package foo\n test_p { p }",
// 		"/a/b/c/policy.rego":      "package bar\n q = 1",
// 		"/a/b/c/policy_test.rego": "package bar\n test_q { q }",
// 		"/a/.manifest":            `{"roots": ["a", "foo"]}`,
// 	}

// 	expectedFiles := map[string]string{
// 		"/a/data.json":       `{"foo": "not-bar"}`,
// 		"/policy.rego":       "package foo\n p = 1",
// 		"/a/b/c/policy.rego": "package bar\n q = 1",
// 		"/a/.manifest":       `{"roots": ["a", "foo"]}`,
// 	}

// 	gzFileIn := map[string]string{
// 		"/archive.tar.gz": "",
// 	}

// 	test.WithTempFS(gzFileIn, func(rootDir string) {
// 		tarballFile := filepath.Join(rootDir, "archive.tar.gz")
// 		f, err := os.Create(tarballFile)
// 		if err != nil {
// 			t.Fatalf("Unexpected error: %s", err)
// 		}

// 		gzFiles := make([][2]string, 0, len(files))
// 		for name, content := range files {
// 			gzFiles = append(gzFiles, [2]string{name, content})
// 		}

// 		_, err = f.Write(archive.MustWriteTarGz(gzFiles).Bytes())
// 		if err != nil {
// 			t.Fatalf("Unexpected error: %s", err)
// 		}
// 		f.Close()

// 		f, err = os.Open(tarballFile)
// 		if err != nil {
// 			t.Fatalf("Unexpected error: %s", err)
// 		}

// 		loader := NewTarballLoaderWithBaseURL(f, tarballFile).WithFilter(func(abspath string, info os.FileInfo, depth int) bool {
// 			return getFilter("*_test.rego", 1)(abspath, info, depth)
// 		})

// 		defer f.Close()

// 		testLoader(t, loader, tarballFile, expectedFiles)
// 	})
// }

// func TestTarballLoaderWithFilterDir(t *testing.T) {

// 	files := map[string]string{
// 		"/a/data.json":            `{"foo": "not-bar"}`,
// 		"/policy.rego":            "package foo\n p = 1",
// 		"/policy_test.rego":       "package foo\n test_p { p }",
// 		"/a/b/c/policy.rego":      "package bar\n q = 1",
// 		"/a/b/c/policy_test.rego": "package bar\n test_q { q }",
// 		"/a/.manifest":            `{"roots": ["a", "foo"]}`,
// 	}

// 	expectedFiles := map[string]string{
// 		"/policy.rego": "package foo\n p = 1",
// 	}

// 	gzFileIn := map[string]string{
// 		"/archive.tar.gz": "",
// 	}

// 	test.WithTempFS(gzFileIn, func(rootDir string) {
// 		tarballFile := filepath.Join(rootDir, "archive.tar.gz")
// 		f, err := os.Create(tarballFile)
// 		if err != nil {
// 			t.Fatalf("Unexpected error: %s", err)
// 		}

// 		gzFiles := make([][2]string, 0, len(files))
// 		for name, content := range files {
// 			gzFiles = append(gzFiles, [2]string{name, content})
// 		}

// 		_, err = f.Write(archive.MustWriteTarGz(gzFiles).Bytes())
// 		if err != nil {
// 			t.Fatalf("Unexpected error: %s", err)
// 		}
// 		f.Close()

// 		f, err = os.Open(tarballFile)
// 		if err != nil {
// 			t.Fatalf("Unexpected error: %s", err)
// 		}

// 		loader := NewTarballLoaderWithBaseURL(f, tarballFile).WithFilter(func(abspath string, info os.FileInfo, depth int) bool {
// 			return getFilter("*_test.rego", 1)(abspath, info, depth)
// 		})

// 		defer f.Close()

// 		tl, ok := loader.(*tarballLoader)
// 		if !ok {
// 			t.Fatal("Expected tar loader instance")
// 		}

// 		tl.skipDir = map[string]struct{}{"a": {}}

// 		fileCount := 0
// 		for {
// 			f, err := tl.NextFile()
// 			if err != nil && err != io.EOF {
// 				t.Fatalf("Unexpected error: %s", err)
// 			} else if err == io.EOF {
// 				break
// 			}

// 			expPath := strings.TrimPrefix(f.URL(), tarballFile)
// 			if f.Path() != expPath {
// 				t.Fatalf("Expected path to be %v but got %v", expPath, f.Path())
// 			}

// 			_, found := expectedFiles[f.Path()]
// 			if !found {
// 				t.Fatalf("Found unexpected file %s", f.Path())
// 			}

// 			fileCount++
// 		}

// 		if fileCount != len(expectedFiles) {
// 			t.Fatalf("Expected to read %d files, read %d", len(expectedFiles), fileCount)
// 		}
// 	})
// }

// func testGetTarballFile(t *testing.T, root string) *os.File {
// 	t.Helper()

// 	tarballFile := filepath.Join(root, "archive.tar.gz")
// 	f, err := os.Create(tarballFile)
// 	if err != nil {
// 		t.Fatalf("Unexpected error: %s", err)
// 	}

// 	gzFiles := make([][2]string, 0, len(archiveFiles))
// 	for name, content := range archiveFiles {
// 		gzFiles = append(gzFiles, [2]string{name, content})
// 	}

// 	_, err = f.Write(archive.MustWriteTarGz(gzFiles).Bytes())
// 	if err != nil {
// 		t.Fatalf("Unexpected error: %s", err)
// 	}
// 	f.Close()

// 	f, err = os.Open(tarballFile)
// 	if err != nil {
// 		t.Fatalf("Unexpected error: %s", err)
// 	}

// 	return f
// }
