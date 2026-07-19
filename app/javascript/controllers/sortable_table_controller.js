import { Controller } from "@hotwired/stimulus"

// Click-to-sort behavior for a plain (non-paginated) <table>, sorting rows
// entirely client-side — no request round trip.
//
// Usage:
//   <table data-controller="sortable-table">
//     <thead><tr>
//       <th data-action="click->sortable-table#sort" data-sort-type="number">Count</th>
//       ...
//     <tbody>...
//
// Cells may set data-sort-value to sort by something other than their
// rendered text (e.g. a raw count behind a formatted "12 (34%)" cell).
export default class extends Controller {
  connect() {
    this.sortedColumnIndex = null
    this.sortedDirection = "asc"
  }

  sort(event) {
    const header = event.currentTarget
    const columnIndex = header.cellIndex
    const sortType = header.dataset.sortType || "string"

    this.sortedDirection =
      this.sortedColumnIndex === columnIndex && this.sortedDirection === "asc" ? "desc" : "asc"
    this.sortedColumnIndex = columnIndex

    const directionMultiplier = this.sortedDirection === "asc" ? 1 : -1
    const tbody = this.element.querySelector("tbody")
    const rows = Array.from(tbody.querySelectorAll("tr"))

    rows.sort((rowA, rowB) => {
      const valueA = this.cellSortValue(rowA, columnIndex, sortType)
      const valueB = this.cellSortValue(rowB, columnIndex, sortType)

      if (valueA < valueB) return -1 * directionMultiplier
      if (valueA > valueB) return 1 * directionMultiplier
      return 0
    })

    rows.forEach((row) => tbody.appendChild(row))
    this.updateHeaderIndicators(header)
  }

  cellSortValue(row, columnIndex, sortType) {
    const cell = row.cells[columnIndex]
    const rawValue = cell.dataset.sortValue ?? cell.textContent.trim()
    return sortType === "number" ? parseFloat(rawValue) || 0 : rawValue.toLowerCase()
  }

  updateHeaderIndicators(activeHeader) {
    this.element.querySelectorAll("thead [data-action]").forEach((header) => {
      header.classList.remove("sorted-asc", "sorted-desc")
    })
    activeHeader.classList.add(this.sortedDirection === "asc" ? "sorted-asc" : "sorted-desc")
  }
}
