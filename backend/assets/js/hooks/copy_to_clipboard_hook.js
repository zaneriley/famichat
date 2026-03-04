const CopyToClipboardHook = {
  mounted() {
    this.el.addEventListener("click", () => {
      const value = this.el.dataset.copyValue;
      navigator.clipboard.writeText(value).then(() => {
        this.pushEvent("copied", {});
      });
    });
  }
};
export default CopyToClipboardHook;
