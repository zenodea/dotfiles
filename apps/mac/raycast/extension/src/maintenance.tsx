import { useEffect, useState } from "react";
import {
  Action,
  ActionPanel,
  Color,
  Detail,
  Icon,
  List,
  showToast,
  Toast,
  useNavigation,
} from "@raycast/api";
import { getAutoStatus, run } from "./lib/dotfiles";

function Output({ title, args }: { title: string; args: string[] }) {
  const [output, setOutput] = useState("Running…");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const out = await run(args);
        setOutput(out || "_(no output)_");
      } catch (e) {
        setOutput(`# Failed\n\n\`\`\`\n${String(e)}\n\`\`\``);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  return (
    <Detail
      isLoading={loading}
      markdown={`# ${title}\n\n\`\`\`\n${output}\n\`\`\``}
      actions={
        <ActionPanel>
          <Action.CopyToClipboard title="Copy Output" content={output} />
        </ActionPanel>
      }
    />
  );
}

export default function Command() {
  const { push } = useNavigation();
  const [auto, setAuto] = useState("");

  useEffect(() => {
    getAutoStatus()
      .then((s) => setAuto(s.enabled ? "on" : "off"))
      .catch(() => setAuto("unknown"));
  }, []);

  async function runToast(title: string, args: string[]) {
    const toast = await showToast({ style: Toast.Style.Animated, title });
    try {
      await run(args);
      toast.style = Toast.Style.Success;
      toast.title = `${title} done`;
    } catch (e) {
      toast.style = Toast.Style.Failure;
      toast.title = `${title} failed`;
      toast.message = String(e);
    }
  }

  return (
    <List searchBarPlaceholder="Maintenance…">
      <List.Item
        title="Update"
        subtitle="git pull, then re-apply the current theme"
        icon={{ source: Icon.Download, tintColor: Color.Blue }}
        actions={
          <ActionPanel>
            <Action
              title="Run Update"
              icon={Icon.Download}
              onAction={() => push(<Output title="dotfiles --update" args={["--update"]} />)}
            />
          </ActionPanel>
        }
      />
      <List.Item
        title="Doctor"
        subtitle="Check symlinks, dependencies, and config drift"
        icon={{ source: Icon.Heartbeat, tintColor: Color.Green }}
        actions={
          <ActionPanel>
            <Action
              title="Run Doctor"
              icon={Icon.Heartbeat}
              onAction={() => push(<Output title="dotfiles --doctor" args={["--doctor"]} />)}
            />
          </ActionPanel>
        }
      />
      <List.Item
        title="Save"
        subtitle="git add + commit + push the repo"
        icon={{ source: Icon.SaveDocument, tintColor: Color.Orange }}
        actions={
          <ActionPanel>
            <Action
              title="Run Save"
              icon={Icon.SaveDocument}
              onAction={() => runToast("Saving", ["--save"])}
            />
          </ActionPanel>
        }
      />
      <List.Item
        title="Sync"
        subtitle="Re-run install.sh (symlink configs)"
        icon={{ source: Icon.Link, tintColor: Color.Purple }}
        actions={
          <ActionPanel>
            <Action
              title="Run Sync"
              icon={Icon.Link}
              onAction={() => push(<Output title="dotfiles --sync" args={["--sync"]} />)}
            />
          </ActionPanel>
        }
      />
      <List.Item
        title="Auto Light/Dark"
        subtitle={`Currently: ${auto}`}
        icon={{ source: Icon.CircleProgress50, tintColor: Color.Yellow }}
        accessories={[{ tag: auto }]}
        actions={
          <ActionPanel>
            <Action
              title="Toggle Auto"
              icon={Icon.CircleProgress50}
              onAction={async () => {
                const next = auto === "on" ? "off" : "on";
                await runToast(`Auto ${next}`, ["--auto", next]);
                setAuto(next);
              }}
            />
            <Action
              title="Show Status"
              icon={Icon.Info}
              onAction={() =>
                push(<Output title="dotfiles --auto status" args={["--auto", "status"]} />)
              }
            />
          </ActionPanel>
        }
      />
    </List>
  );
}
