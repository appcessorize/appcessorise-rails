import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar"]
  static values = { observe: String }

  connect() {
    const observed = document.getElementById(this.observeValue)
    if (!observed) return

    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          this.barTarget.classList.add("translate-y-full")
          this.barTarget.classList.remove("translate-y-0")
        } else {
          this.barTarget.classList.remove("translate-y-full")
          this.barTarget.classList.add("translate-y-0")
        }
      })
    }, { threshold: 0 })

    this.observer.observe(observed)
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }
}
