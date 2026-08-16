import SwiftUI

/// Reúne las dos bandejas de baja presión sin perderlas al dar al calendario
/// un lugar permanente en la barra inferior.
struct TasksHubView: View {
    @State private var selection: TaskState = .after

    var body: some View {
        VStack(spacing: 0) {
            Picker("Lista", selection: $selection) {
                Text("Después").tag(TaskState.after)
                Text("Algún día").tag(TaskState.someday)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, SRDesign.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 2)

            TaskListView(state: selection)
                .id(selection)
                .transition(.opacity)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .animation(SRDesign.quickAnimation, value: selection)
    }
}
