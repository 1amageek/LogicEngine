import LogicIR
import LogicKernelCore

extension RTLEventWorkspace {
    func stabilize(context: inout LogicKernelContext) throws(LogicKernelError) {
        try plan.design.withProgram { _, _, _, _, _, _, processes throws(LogicKernelError) in
            while true {
                try context.charge(.workUnits)
                var active = false
                for process in processes.indices {
                    try context.charge(.workUnits)
                    if case .flipFlop(let clock, let edge, let reset) = processes[process].control {
                        let current = try expression(clock, context: &context).bit(at: 0)
                        var triggered = LogicCellEventSemantics.edge(from: clocks[process], to: current, rising: edge == .rising)
                        clocks[process] = current
                        if let reset {
                            let value = try expression(reset.signal, context: &context).bit(at: 0)
                            if LogicCellEventSemantics.edge(from: resets[process], to: value, rising: reset.activeHigh) { triggered = true }
                            resets[process] = value
                        }
                        activated[process] = triggered; dirty[process] = false
                    } else { activated[process] = dirty[process] }
                    active = active || activated[process]
                }
                // A clock/input transaction may expose an Active-region race even
                // when the statically admitted circuit is otherwise deterministic.
                for reader in processes.indices where activated[reader] {
                    guard case .flipFlop = processes[reader].control else { continue }
                    for writer in processes.indices where activated[writer] && reader != writer {
                        if case .flipFlop = processes[writer].control { continue }
                        for bit in 0..<plan.bitCount {
                            try context.charge(.workUnits)
                            if plan.reads[reader * plan.bitCount + bit] && plan.writes[writer * plan.bitCount + bit] {
                                throw .unsupported("Input event exposes an Active-region blocking read/write race")
                            }
                        }
                    }
                }
                if active {
                    for process in processes.indices where activated[process] {
                        dirty[process] = false
                        try execute(process: process, context: &context)
                    }
                    continue
                }
                if try !commitNBA(context: &context) { break }
            }
        }
    }
}
