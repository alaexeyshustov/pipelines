import { application } from "./application"
import AccordionController from "./accordion_controller"
import AgentSelectController from "./agent_select_controller"
import BatchController from "./batch_controller"
import DialogController from "./dialog_controller"
import DisclosureController from "./disclosure_controller"
import ScoreChartController from "./evaluation/score_chart_controller"
import SelectSearchController from "./select_search_controller"

application.register("accordion", AccordionController)
application.register("agent-select", AgentSelectController)
application.register("batch", BatchController)
application.register("dialog", DialogController)
application.register("disclosure", DisclosureController)
application.register("evaluation--score-chart", ScoreChartController)
application.register("select-search", SelectSearchController)

