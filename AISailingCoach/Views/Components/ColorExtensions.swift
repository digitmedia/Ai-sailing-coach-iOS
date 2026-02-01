//
//  ColorExtensions.swift
//  AISailingCoach
//
//  Spatial Sail design system colors
//  Based on Figma design specifications
//

import SwiftUI

// MARK: - Spatial Sail Color Palette

extension Color {
    // MARK: - Primary Accent Colors

    /// Spatial Sail Yellow - Primary accent color
    /// Hex: #FDB714
    static let spatialYellow = Color(red: 0.99, green: 0.72, blue: 0.08)

    /// Spatial Sail Turquoise - Secondary accent color
    /// Hex: #A5D8DD
    static let spatialTurquoise = Color(red: 0.65, green: 0.85, blue: 0.87)

    // MARK: - Status Colors

    /// Performance Red - Used for low performance and port layline
    /// Hex: #ef4444
    static let performanceRed = Color(red: 0.94, green: 0.27, blue: 0.27)

    /// Layline Green - Used for starboard layline
    /// Hex: #10b981
    static let laylineGreen = Color(red: 0.06, green: 0.73, blue: 0.51)

    // MARK: - Background Colors

    /// Dark Gray - Used for panel backgrounds
    /// Hex: #111827
    static let darkGray = Color(red: 0.07, green: 0.09, blue: 0.15)

    /// Darker Gray - Used for bezel effects
    /// Hex: #1f2937
    static let darkerGray = Color(red: 0.12, green: 0.16, blue: 0.22)

    // MARK: - Helper Functions

    /// Get performance color based on percentage
    /// Yellow for >= 85%, Red for < 85%
    static func performanceColor(for percentage: Int) -> Color {
        percentage >= 85 ? .spatialYellow : .performanceRed
    }
}

// MARK: - Gradient Definitions

extension LinearGradient {
    /// Panel background gradient (top to bottom)
    static let panelBackground = LinearGradient(
        colors: [Color.darkGray, Color.black],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Bezel background gradient (top to bottom)
    static let bezelBackground = LinearGradient(
        colors: [Color.darkerGray, Color.darkGray],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - View Modifiers

extension View {
    /// Apply standard panel styling with yellow border
    func panelStyle() -> some View {
        self
            .background(Color.black.opacity(0.8))
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.spatialYellow, lineWidth: 2)
            )
    }

    /// Apply bezel container styling
    func bezelStyle() -> some View {
        self
            .padding(12)
            .background(LinearGradient.bezelBackground)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Font Styling

extension Font {
    /// Large data display font (56pt bold)
    static let dataDisplay = Font.system(size: 56, weight: .bold)

    /// Medium data display font (36pt bold)
    static let dataDisplayMedium = Font.system(size: 36, weight: .bold)

    /// Label font (18pt semibold with tracking)
    static let dataLabel = Font.system(size: 18, weight: .semibold)

    /// Unit font (16pt regular)
    static let dataUnit = Font.system(size: 16, weight: .regular)

    /// Small label font (10pt)
    static let smallLabel = Font.system(size: 10, weight: .regular)
}

// MARK: - Label Style

struct DataLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.dataLabel)
            .foregroundColor(.spatialYellow)
            .tracking(2) // 0.1em letter spacing
    }
}

extension View {
    func dataLabelStyle() -> some View {
        modifier(DataLabelStyle())
    }
}
