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
        HStack(spacing: 16) {
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.spatialYellow)
                .tracking(2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.white)
                    .monospacedDigit()

                Text(unit)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.black.opacity(0.8))
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.spatialYellow, lineWidth: 2)
        )
    }
}

// MARK: - Extended Data Box (for additional metrics)

struct ExtendedDataBox: View {
    let label: String
    let value: String
    let subValue: String?
    let accentColor: Color

    init(
        label: String,
        value: String,
        subValue: String? = nil,
        accentColor: Color = .spatialYellow
    ) {
        self.label = label
        self.value = value
        self.subValue = subValue
        self.accentColor = accentColor
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accentColor)
                .tracking(1.5)

            Text(value)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
                .monospacedDigit()

            if let subValue = subValue {
                Text(subValue)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.black.opacity(0.8))
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Wind Data Row

struct WindDataRow: View {
    let trueWindSpeed: Double
    let trueWindAngle: Double
    let apparentWindSpeed: Double

    var body: some View {
        HStack(spacing: 12) {
            ExtendedDataBox(
                label: "TWS",
                value: String(format: "%.1f", trueWindSpeed),
                subValue: "kts",
                accentColor: .spatialTurquoise
            )

            ExtendedDataBox(
                label: "TWA",
                value: "\(Int(trueWindAngle))°",
                accentColor: .spatialTurquoise
            )

            ExtendedDataBox(
                label: "AWS",
                value: String(format: "%.1f", apparentWindSpeed),
                subValue: "kts",
                accentColor: .spatialYellow
            )
        }
    }
}

// MARK: - Previews

#Preview("Data Boxes") {
    DataBoxesView(boatSpeed: 6.8, targetSpeed: 7.5)
        .padding()
        .background(Color.black)
}

#Preview("Extended Data Box") {
    ExtendedDataBox(
        label: "VMG",
        value: "5.2",
        subValue: "kts"
    )
    .frame(width: 100)
    .padding()
    .background(Color.black)
}

#Preview("Wind Data Row") {
    WindDataRow(
        trueWindSpeed: 12.5,
        trueWindAngle: 42,
        apparentWindSpeed: 15.2
    )
    .padding()
    .background(Color.black)
}
