import SwiftUI
import AppKit

public struct FilesPanel: View {
    @Bindable var state: IslandState
    @State private var isTargeted: Bool = false
    
    public init(state: IslandState) {
        self.state = state
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // Panel Heading
            HStack {
                HStack(spacing: 9) {
                    Text("Под рукой")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.96, green: 0.96, blue: 0.97))
                    
                    Text("\(state.shelfFiles.count) \(pluralFiles(state.shelfFiles.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.61, green: 0.61, blue: 0.64))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                
                Spacer()
                
                Button(action: {
                    selectFileFromDisk()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.56))
                        .frame(width: 28, height: 28)
                        .background(Color(red: 0.14, green: 0.14, blue: 0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Выбрать файл на диске")
            }
            .frame(height: 24)
            
            // File Cards Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    if state.shelfFiles.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 26))
                                .foregroundColor(isTargeted ? Color.white : Color(red: 0.51, green: 0.51, blue: 0.55))
                            
                            Text("Перетащите любой файл из Finder сюда")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isTargeted ? Color.white : Color(red: 0.51, green: 0.51, blue: 0.55))
                        }
                        .frame(width: 592, height: 150)
                        .background(isTargeted ? Color(red: 0.14, green: 0.14, blue: 0.16) : Color(red: 0.07, green: 0.07, blue: 0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    } else {
                        ForEach(state.shelfFiles) { file in
                            RealFileCardView(file: file) {
                                state.removeShelfFile(id: file.id)
                            }
                        }
                    }
                }
            }
            .frame(height: 154)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
            
            // Bottom Shelf Bar
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.63, green: 0.63, blue: 0.66))
                
                Text("Перетащите файл сюда. Заберите, когда понадобится.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(red: 0.47, green: 0.47, blue: 0.49))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Color(red: 0.06, green: 0.06, blue: 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 24)
        .frame(width: 640)
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        self.state.addRealFile(url: url)
                    }
                }
            }
        }
        return true
    }
    
    private func selectFileFromDisk() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                state.addRealFile(url: url)
            }
        }
    }
    
    private func pluralFiles(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "файл" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "файла" }
        return "файлов"
    }
}

private struct RealFileCardView: View {
    let file: RealShelfFile
    let onRemove: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Real macOS System Icon for the file
                let iconImage = NSWorkspace.shared.icon(forFile: file.url.path)
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .frame(height: 85)
                
                Text(file.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.96, green: 0.96, blue: 0.97))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                
                Text(file.sizeFormatted)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.48))
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            .frame(width: 185, height: 150)
            .background(isHovered ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color(red: 0.08, green: 0.08, blue: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                NSWorkspace.shared.open(file.url)
            }
            .onDrag {
                let provider = NSItemProvider(contentsOf: file.url) ?? NSItemProvider(object: file.url as NSURL)
                provider.suggestedName = file.name
                return provider
            }
            
            // Remove button
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(red: 0.76, green: 0.76, blue: 0.79))
                        .frame(width: 20, height: 20)
                        .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .onHover { isHovered = $0 }
    }
}
