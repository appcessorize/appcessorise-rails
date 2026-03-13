import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mainImage", "thumbnail"]

  select(event) {
    const index = event.currentTarget.dataset.index

    this.mainImageTargets.forEach((img, i) => {
      img.classList.toggle("hidden", i.toString() !== index)
    })

    this.thumbnailTargets.forEach((thumb, i) => {
      if (i.toString() === index) {
        thumb.classList.add("ring-2", "ring-[#1a1a1a]")
        thumb.classList.remove("ring-1", "ring-[#e5e5e5]")
      } else {
        thumb.classList.remove("ring-2", "ring-[#1a1a1a]")
        thumb.classList.add("ring-1", "ring-[#e5e5e5]")
      }
    })
  }
}
