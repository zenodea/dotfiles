import Quickshell
import qs.greeter

ShellRoot {
    Variants {
        model: Quickshell.screens

        GreeterWindow {
            required property ShellScreen modelData

            screen: modelData
        }
    }
}
