//@ pragma UseQApplication

import Quickshell
import qs.bar

ShellRoot {
    Variants {
        model: Quickshell.screens

        Scope {
            id: scope

            required property ShellScreen modelData

            Exclusions {
                screen: scope.modelData
            }

            Frame {
                modelData: scope.modelData
            }
        }
    }
}
