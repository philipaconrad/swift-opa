import AST
import Foundation

extension OPA.Engine {
    /// ``BundleCache`` serves as a store for validated bundles.
    ///
    /// This allows the runtime to minimize validation costs when
    /// preparing queries. Per-bundle ``OPA/Bundle/validate()`` results and
    /// the cross-bundle overlap check are computed eagerly on insertion and
    /// cached, so repeated ``prepareForEvaluation(query:)`` calls only pay
    /// validation cost when the bundle set actually changes.
    final class BundleCache: @unchecked Sendable {
        /// Cached state for a single bundle.
        private struct Entry {
            let bundle: OPA.Bundle
            /// `nil` if the bundle passed ``OPA/Bundle/validate()``, otherwise
            /// the error thrown during validation.
            let validationError: Error?
        }

        /// Bundles keyed by name, along with their cached validation result.
        private var entries: [String: Entry] = [:]

        /// Cached result of the most recent overlap check across `entries`.
        /// `nil` means the last check succeeded.
        private var overlapError: Error?

        /// Synchronizes access to the mutable cache state.
        private let lock = NSLock()

        /// Initializes the cache with a set of bundles, eagerly validating
        /// all bundles, and running the overlap check.
        public init(bundles: [String: OPA.Bundle] = [:]) {
            for (name, bundle) in bundles {
                entries[name] = Self.makeEntry(bundle: bundle)
            }
            recomputeOverlapLocked()
        }

        /// Copy constructor. No validation is performed, but existing
        /// validation results are copied over.
        public init(copying other: BundleCache) {
            other.lock.lock()
            defer { other.lock.unlock() }
            self.entries = other.entries
            self.overlapError = other.overlapError
        }

        /// Adds or replaces a single bundle. Validates the bundle and
        /// recomputes the overlap check. A name collision overwrites the
        /// previous entry.
        public func add(name: String, bundle: OPA.Bundle) {
            lock.lock()
            defer { lock.unlock() }
            entries[name] = Self.makeEntry(bundle: bundle)
            recomputeOverlapLocked()
        }

        /// Adds or replaces multiple bundles at once. More efficient than
        /// calling ``add(name:bundle:)`` repeatedly because the overlap check
        /// only runs once at the end.
        public func add(bundles: [String: OPA.Bundle]) {
            guard !bundles.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }
            for (name, bundle) in bundles {
                entries[name] = Self.makeEntry(bundle: bundle)
            }
            recomputeOverlapLocked()
        }

        /// Removes a single bundle from the cache. If the cache currently has
        /// an overlap error, the overlap check is recomputed (since removing
        /// a bundle may resolve the overlap). Otherwise the overlap check is
        /// skipped, because removing bundles can only reduce overlap.
        ///
        /// - Returns: `true` if a bundle with the given name was removed.
        @discardableResult
        public func remove(name: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard entries.removeValue(forKey: name) != nil else {
                return false
            }
            if overlapError != nil {
                recomputeOverlapLocked()
            }
            return true
        }

        /// Removes multiple bundles from the cache. More efficient than
        /// calling ``remove(name:)`` repeatedly, since the overlap check is
        /// at most recomputed once at the end (and only if the cache
        /// previously had an overlap error).
        ///
        /// - Returns: The names that were actually removed.
        @discardableResult
        public func remove(names: some Sequence<String>) -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            var removed: Set<String> = []
            for name in names {
                if entries.removeValue(forKey: name) != nil {
                    removed.insert(name)
                }
            }
            if !removed.isEmpty, overlapError != nil {
                recomputeOverlapLocked()
            }
            return removed
        }

        /// Removes all bundles from the cache and clears the cached overlap
        /// result (an empty bundle set trivially has no overlap).
        public func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            entries.removeAll()
            overlapError = nil
        }

        /// Returns the cached set of bundles, throwing if either the overlap
        /// check or any individual bundle validation failed.
        ///
        /// Overlap errors are surfaced first, then per-bundle validation
        /// errors in sorted name order.
        public func validated() throws -> [String: OPA.Bundle] {
            let (snapshot, err): ([String: Entry], Error?) = {
                lock.lock()
                defer { lock.unlock() }
                return (entries, overlapError)
            }()
            if let err { throw err }
            for (name, entry) in snapshot.sorted(by: { $0.key < $1.key }) {
                if let err = entry.validationError {
                    throw RegoError(
                        code: .bundleLoadError,
                        message: "failed to validate bundle \(name)",
                        cause: err
                    )
                }
            }
            return snapshot.mapValues { $0.bundle }
        }

        /// Eagerly runs ``OPA/Bundle/validate()`` and captures any error.
        private static func makeEntry(bundle: OPA.Bundle) -> Entry {
            do {
                try bundle.validate()
                return Entry(bundle: bundle, validationError: nil)
            } catch {
                return Entry(bundle: bundle, validationError: error)
            }
        }

        /// Recomputes and caches the overlap check across all current entries.
        /// Must be called with `lock` held.
        private func recomputeOverlapLocked() {
            let bundles = entries.mapValues { $0.bundle }
            do {
                try OPA.Bundle.checkBundlesForOverlap(bundleSet: bundles)
                overlapError = nil
            } catch {
                overlapError = error
            }
        }

    }
}
