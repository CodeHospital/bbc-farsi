import { Controller } from "@hotwired/stimulus"

// Instant client-side text filter for a table's rows.
//
// Usage:
//   <div data-controller="table-filter">
//     <input data-table-filter-target="input" data-action="input->table-filter#filter">
//     <span data-table-filter-target="count"></span>
//     <tr data-table-filter-target="row" data-search-text="lowercased words">...</tr>
//     <div data-table-filter-target="empty" hidden>No matches</div>
//
// Rows fall back to their text content when data-search-text is missing.
// Rows replaced or removed by Turbo Streams are picked up automatically.
export default class extends Controller {
  static targets = ["input", "row", "count", "empty"]

  connect() {
    const tableBody = this.element.querySelector("tbody")
    if (tableBody) {
      this.rowObserver = new MutationObserver(() => this.filter())
      this.rowObserver.observe(tableBody, { childList: true })
    }
  }

  disconnect() {
    this.rowObserver?.disconnect()
  }

  filter() {
    const searchTerms = (this.hasInputTarget ? this.inputTarget.value : "")
      .toLowerCase()
      .split(/\s+/)
      .filter(Boolean)

    let visibleRowCount = 0
    this.rowTargets.forEach((row) => {
      const rowSearchText = (row.dataset.searchText ?? row.textContent).toLowerCase()
      const rowMatches = searchTerms.every((term) => rowSearchText.includes(term))
      row.hidden = !rowMatches
      if (rowMatches) visibleRowCount += 1
    })

    if (this.hasCountTarget) this.countTarget.textContent = visibleRowCount
    if (this.hasEmptyTarget) this.emptyTarget.hidden = visibleRowCount > 0
  }
}
