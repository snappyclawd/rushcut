import SwiftUI

/// A compact, tappable tag pill
struct TagPill: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? .white : (isHovered ? color : .secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                isSelected ? color : (isHovered ? color.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .cornerRadius(8)
            .onHover { over in isHovered = over }
            .onTapGesture { action() }
            .animation(.easeInOut(duration: 0.1), value: isSelected)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

/// Flow layout that wraps children to the next line when they exceed width
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
    
    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }
        
        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
