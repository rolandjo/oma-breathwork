import QtQuick
import Quickshell.Io

// One process at a time per writer; persist.py also locks across instances.
QtObject {
  id: root
  property var queue: []
  property var active: null
  signal finished(bool ok, string message, var context)

  function submit(path, operation, value, context) {
    queue.push({ path: path, operation: operation, value: value, context: context || {} })
    drain()
  }

  function drain() {
    if (active || !queue.length) return
    active = queue.shift()
    var helper = decodeURIComponent(Qt.resolvedUrl("persist.py").toString().replace(/^file:\/\//, ""))
    worker.command = ["python3", helper, active.path, active.operation, JSON.stringify(active.value)]
    worker.running = true
  }

  property Process worker: Process {
    stderr: StdioCollector { id: errors; waitForEnd: true }
    onExited: function(exitCode, exitStatus) {
      var job = root.active
      root.active = null
      root.finished(exitCode === 0, exitCode === 0 ? "" : (errors.text.trim() || "Unable to write data"), job.context)
      Qt.callLater(root.drain)
    }
  }
}
