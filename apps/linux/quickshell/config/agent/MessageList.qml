import QtQuick
import QtQml.Models
import qs.services

ListView {
    id: root

    property bool stick: true

    signal returnFocus

    // scrolls by delta pixels; following new messages resumes once back at the bottom
    function scroll(delta: real): void {
        const top = originY;
        const bottom = originY + Math.max(contentHeight - height, 0);
        contentY = Math.max(top, Math.min(contentY + delta, bottom));
        stick = contentY >= bottom - 1;
    }

    clip: true
    spacing: 16
    boundsBehavior: Flickable.StopAtBounds
    model: Agent.messages

    onMovementEnded: stick = atYEnd
    onContentHeightChanged: {
        if (stick)
            positionViewAtEnd();
    }
    onHeightChanged: {
        if (stick)
            positionViewAtEnd();
    }

    delegate: DelegateChooser {
        role: "role"

        DelegateChoice {
            roleValue: "user"

            UserEntry {}
        }

        DelegateChoice {
            roleValue: "tool"

            ToolRow {}
        }

        DelegateChoice {
            roleValue: "approval"

            ApprovalCard {}
        }

        DelegateChoice {
            roleValue: "question"

            QuestionCard {}
        }

        DelegateChoice {
            roleValue: "error"

            ErrorEntry {}
        }

        DelegateChoice {
            AssistantEntry {}
        }
    }
}
