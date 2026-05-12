import { application } from "./application"
import AccordionController from "./accordion_controller"
import BatchController from "./batch_controller"
import DialogController from "./dialog_controller"
import ScoreChartController from "./evaluation/score_chart_controller"
import SelectSearchController from "./select_search_controller"

application.register("accordion", AccordionController)
application.register("batch", BatchController)
application.register("dialog", DialogController)
application.register("evaluation--score-chart", ScoreChartController)
application.register("select-search", SelectSearchController)

