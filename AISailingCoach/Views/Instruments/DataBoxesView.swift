//
//  DataBoxesView.swift
//  AISailingCoach
//
//  Speed data display boxes showing boat speed and target speed
//

import SwiftUI

struct DataBoxesView: View {
    let boatSpeed: Double
    let targetSpeed: Double

    var body: some View {
        HStack(spacing: 12) {
            DataBox(
                label: "BOAT SPEED",
                value: boatSpeed,
                unit: "kts"
            )

            DataBox(
                label: "TARGET",
                value: targetSpeed,
                unit: "kts"
            )
        }
    }
}

// MARK: - Individual Data Box

struct DataBox: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.spatialYellow)
                .tracking(1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text(unit)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.8))
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.spatialYellow, lineWidth: 2)
        )
    }
}

// MARK: - Previews

#Preview("Data Boxes") {
    DataBoxesView(boatSpeed: 6.8, targetSpeed: 7.5)
        .padding()
        .background(Color.black)
}
