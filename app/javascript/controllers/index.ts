import { application } from "./application"
import BatchController from "./batch_controller"
import DialogController from "./dialog_controller"

application.register("batch", BatchController)
application.register("dialog", DialogController)

