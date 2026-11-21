pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property string theme: "/usr/share/icons/breeze"

    readonly property var folders: ({
            "Downloads": "folder-download",
            "Documents": "folder-documents",
            "Pictures": "folder-pictures",
            "Music": "folder-music",
            "Videos": "folder-videos",
            "Desktop": "user-desktop",
            ".git": "folder-git"
        })

    readonly property var kinds: ({
            "image-x-generic": ["png", "jpg", "jpeg", "gif", "webp", "bmp", "avif", "heic", "ico", "tiff", "svg"],
            "video-x-generic": ["mp4", "mkv", "webm", "mov", "avi", "m4v"],
            "audio-x-generic": ["mp3", "flac", "wav", "ogg", "opus", "m4a", "aac"],
            "package-x-generic": ["zip", "tar", "gz", "tgz", "xz", "zst", "bz2", "7z", "rar", "deb", "rpm"],
            "application-pdf": ["pdf"],
            "x-office-document": ["doc", "docx", "odt", "rtf"],
            "x-office-spreadsheet": ["xls", "xlsx", "ods", "csv"],
            "x-office-presentation": ["ppt", "pptx", "odp"],
            "text-markdown": ["md"],
            "text-html": ["html", "htm"],
            "application-json": ["json"],
            "text-x-python": ["py"],
            "application-x-shellscript": ["sh", "bash", "zsh", "fish"],
            "application-javascript": ["js", "mjs", "ts", "tsx", "jsx"],
            "text-x-lua": ["lua"],
            "text-css": ["css"],
            "text-x-qml": ["qml"],
            "text-x-rust": ["rs"],
            "text-x-csrc": ["c", "h", "cpp", "hpp", "cc"],
            "text-x-script": ["go", "java", "kt", "swift", "rb", "php", "cs", "sql", "xml", "toml", "yaml", "yml", "nix", "conf", "ini", "rasi", "vim", "zig", "dart"]
        })

    readonly property var byExtension: {
        const map = {};
        for (const name in kinds)
            for (const extension of kinds[name])
                map[extension] = name;
        return map;
    }

    function themed(group: string, name: string): string {
        return Quickshell.iconPath(name, true) || `file://${theme}/${group}/32/${name}.svg`;
    }

    function folder(name: string): string {
        return themed("places", folders[name] ?? "folder");
    }

    function file(name: string): string {
        const dot = name.lastIndexOf(".");
        return themed("mimetypes", (dot > 0 ? byExtension[name.slice(dot + 1).toLowerCase()] : undefined) ?? "text-x-generic");
    }
}
