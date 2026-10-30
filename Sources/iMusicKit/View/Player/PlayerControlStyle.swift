import SwiftUI

struct PlayerControlStyle: ButtonStyle {
    /// Disables decorative scaling and animation when the user requests reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// System enabled state propagated from the surrounding playback control group.
    @Environment(\.isEnabled) private var isEnabled
    /// Adds a transient press surface while retaining the control's stable layout and hit region.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? Color.primary.opacity(0.07) : .clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
    }
}
