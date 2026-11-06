// Dotfiles Zen live theme loader. Autoconfig skips this first line.
// Registers chrome/dotfiles-theme.css as a user sheet and swaps it whenever the
// file changes, so a theme switch needs no restart. The dotfiles.zen.live pref
// (default branch, never saved) turns off userChrome.css's startup @import.
// Autoconfig has Services/Cc/Ci but no IOUtils/PathUtils: plain nsIFile only.
try {
  Services.prefs.getDefaultBranch("").setBoolPref("dotfiles.zen.live", true);
  Services.obs.addObserver(function started() {
    Services.obs.removeObserver(started, "final-ui-startup");
    const sss = Cc["@mozilla.org/content/style-sheet-service;1"]
      .getService(Ci.nsIStyleSheetService);
    const chromeFile = name => {
      const file = Services.dirsvc.get("UChrm", Ci.nsIFile);
      file.append(name);
      return file;
    };
    let sheet = null, stamp;

    function apply() {
      try {
        const css = chromeFile("dotfiles-theme.css");
        const mtime = css.exists() ? css.lastModifiedTime : null;
        if (mtime === stamp) return;
        stamp = mtime;
        // A fresh query per version bypasses the sheet cache; register the new
        // sheet before dropping the old one so the UI never flashes unthemed.
        const next = mtime === null ? null
          : Services.io.newURI(Services.io.newFileURI(css).spec + "?v=" + mtime);
        if (next) sss.loadAndRegisterSheet(next, sss.USER_SHEET);
        if (sheet) sss.unregisterSheet(sheet, sss.USER_SHEET);
        sheet = next;
      } catch (e) {
        Cu.reportError(e);
      }
    }

    apply();
    const timer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
    timer.initWithCallback(apply, 500, Ci.nsITimer.TYPE_REPEATING_SLACK);
    globalThis.dotfilesZenTimer = timer; // Keep the timer alive.

    // Lets render() see that this running Zen applies changes without restart.
    const pid = Services.appinfo.processID + "\n";
    const out = Cc["@mozilla.org/network/file-output-stream;1"]
      .createInstance(Ci.nsIFileOutputStream);
    out.init(chromeFile(".dotfiles-live"), 0x02 | 0x08 | 0x20, 0o600, 0);
    out.write(pid, pid.length);
    out.close();
  }, "final-ui-startup");
} catch (e) {
  Cu.reportError(e);
}
