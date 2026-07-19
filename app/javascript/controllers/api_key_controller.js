import { Controller } from "@hotwired/stimulus"

// Reveals / masks an API key and copies it to the clipboard.
// The real key lives in the `key` value; the input shows a masked version
// until the user reveals it.
export default class extends Controller {
  static targets = ["input", "revealLabel", "copyLabel"]
  static values = { key: String }

  connect() {
    this.revealed = false
    this.render()
  }

  toggle() {
    this.revealed = !this.revealed
    this.render()
  }

  copy() {
    navigator.clipboard.writeText(this.keyValue).then(() => {
      if (!this.hasCopyLabelTarget) return
      const original = this.copyLabelTarget.textContent
      this.copyLabelTarget.textContent = "Copied!"
      setTimeout(() => { this.copyLabelTarget.textContent = original }, 1500)
    })
  }

  render() {
    if (this.hasInputTarget) {
      this.inputTarget.value = this.revealed ? this.keyValue : this.masked()
    }
    if (this.hasRevealLabelTarget) {
      this.revealLabelTarget.textContent = this.revealed ? "Hide" : "Reveal"
    }
  }

  masked() {
    const key = this.keyValue || ""
    if (key.length <= 10) return "•".repeat(key.length)
    return `${key.slice(0, 6)}${"•".repeat(18)}${key.slice(-4)}`
  }
}
