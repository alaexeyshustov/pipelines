import { application } from "./application"
import AccordionController from "./accordion_controller"
import BatchController from "./batch_controller"
import DialogController from "./dialog_controller"

application.register("accordion", AccordionController)
application.register("batch", BatchController)
application.register("dialog", DialogController)

