import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mainImage", "thumbnail"]

  select(event) {
    const index = event.currentTarget.dataset.index

    // Update main image
    this.mainImageTargets.forEach((img, i) => {
      if (i.toString() === index) {
        img.classList.remove("hidden")
      } else {
        img.classList.add("hidden")
      }
    })

    // Update thumbnail active state
    this.thumbnailTargets.forEach((thumb, i) => {
      if (i.toString() === index) {
        thumb.classList.add("ring-2", "ring-[oklch(14%_0.005_285.823)]")
        thumb.classList.remove("ring-1", "ring-[oklch(88%_0_0)]")
      } else {
        thumb.classList.remove("ring-2", "ring-[oklch(14%_0.005_285.823)]")
        thumb.classList.add("ring-1", "ring-[oklch(88%_0_0)]")
      }
    })
  }
}
