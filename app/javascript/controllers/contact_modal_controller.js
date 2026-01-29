import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "form", "success"]

  open() {
    this.modalTarget.showModal()
  }

  close() {
    this.modalTarget.close()
  }

  formSubmitEnd(event) {
    if (event.detail.success) {
      this.successTarget.classList.remove("hidden")
      this.formTarget.reset()
      setTimeout(() => {
        this.modalTarget.close()
        this.successTarget.classList.add("hidden")
      }, 2000)
    }
  }
}
