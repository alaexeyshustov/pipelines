import { Controller } from "@hotwired/stimulus"
import { Chart, LineController, LineElement, PointElement, LinearScale, CategoryScale, Tooltip } from "chart.js"

Chart.register(LineController, LineElement, PointElement, LinearScale, CategoryScale, Tooltip)

interface DataPoint {
  created_at: string
  avg_score: number | null
}

export default class extends Controller {
  static values = { points: Array }

  declare pointsValue: DataPoint[]

  connect() {
    const canvas = this.element.querySelector("canvas")
    if (!canvas) return

    const labels = this.pointsValue.map(p => p.created_at)
    const scores = this.pointsValue.map(p => p.avg_score)

    new Chart(canvas as HTMLCanvasElement, {
      type: "line",
      data: {
        labels,
        datasets: [
          {
            label: "Avg Score",
            data: scores,
            borderColor: "#6366f1",
            backgroundColor: "rgba(99, 102, 241, 0.1)",
            tension: 0.3,
            fill: true,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          y: { min: 0, max: 5, ticks: { stepSize: 1 } },
        },
        plugins: { tooltip: { enabled: true } },
      },
    })
  }
}
