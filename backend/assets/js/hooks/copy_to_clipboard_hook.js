const CopyToClipboardHook = {
  mounted() {
    this.el.addEventListener("click", () => {
      const value = this.el.dataset.copyValue;

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard
          .writeText(value)
          .then(() => {
            this.pushEvent("copied", {});
          })
          .catch(() => {
            this._fallbackCopy(value);
          });
      } else {
        this._fallbackCopy(value);
      }
    });
  },

  _fallbackCopy(value) {
    // Attempt textarea-based fallback for older browsers / insecure contexts
    const textarea = document.createElement("textarea");
    textarea.value = value;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();

    try {
      const ok = document.execCommand("copy");
      if (ok) {
        this.pushEvent("copied", {});
      } else {
        this.pushEvent("copy-failed", {});
      }
    } catch (_e) {
      this.pushEvent("copy-failed", {});
    } finally {
      document.body.removeChild(textarea);
    }
  }
};
export default CopyToClipboardHook;
