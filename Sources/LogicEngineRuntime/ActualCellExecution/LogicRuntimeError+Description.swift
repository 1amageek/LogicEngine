import Foundation
import LogicKernelCore

extension LogicRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .input(let error): return "Input failed: \(error)"
        case .codec(let error): return "Codec failed: \(error)"
        case .library(let error): return "Library preparation failed: \(error)"
        case .kernel(let error): return "Kernel failed: \(error)"
        case .proof(let error): return "Proof failed: \(error)"
        case .timing(let error): return "STA failed: \(error)"
        case .persistence(let error): return "Artifact persistence failed: \(error)"
        case .different: return "The actual-cell candidate has a replayed functional difference"
        case .inconclusive(let reason): return "Equivalence is unproved: \(reason)"
        case .constraint(let reason): return "This candidate fails a required constraint: \(reason)"
        case .unsupported(let reason): return "Unsupported execution requirement: \(reason)"
        }
    }
}
