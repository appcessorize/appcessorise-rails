import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.showTab(0)
  }

  select(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    this.showTab(index)
  }

  showTab(index) {
    this.tabTargets.forEach((tab, i) => {
      if (i === index) {
        tab.classList.add("border-[#1a1a1a]", "text-[#1a1a1a]")
        tab.classList.remove("border-transparent", "text-[#999]")
      } else {
        tab.classList.remove("border-[#1a1a1a]", "text-[#1a1a1a]")
        tab.classList.add("border-transparent", "text-[#999]")
      }
    })

    this.panelTargets.forEach((panel, i) => {
      panel.classList.toggle("hidden", i !== index)
    })
  }
}
