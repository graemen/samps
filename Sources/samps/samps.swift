import SwiftUI
import AppKit
import AVFoundation

@main
struct SampsApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 980, minHeight: 640)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showingAddSheet = false

    var body: some View {
        NavigationSplitView {
            SidebarView(showingAddSheet: $showingAddSheet)
        } content: {
            DetailView()
        } detail: {
            InspectorView()
        }
        .navigationTitle("SAMPS!")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Sample", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSampleSheet()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var showingAddSheet: Bool
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Samples")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(library.filteredSamples.count)")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.primary)
                Button {
                    library.refreshMissingMetadata()
                } label: {
                    if library.isRefreshingMetadata {
                        Label("Refreshing...", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(library.isRefreshingMetadata)
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add sample")
            }
            .padding(.horizontal)

            HStack {
                TextField("Search tags or names", text: $library.searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    library.searchText = ""
                } label: {
                    Label("", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
            .padding(.horizontal)
            .padding(.top, 12)

            if library.isRefreshingMetadata || library.refreshProgress > 0 && library.refreshProgress < 1 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: library.refreshProgress)
                    Text(library.refreshStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            HStack(spacing: 8) {
                Picker("Sort", selection: $library.sortKey) {
                    ForEach(SortKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .pickerStyle(.menu)

                Picker("Order", selection: $library.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)

            Divider()

            if library.isImporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: library.importProgress)
                    Text(library.importStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            List(selection: $library.selection) {
                ForEach(library.filteredSamples) { sample in
                    SampleRow(sample: sample)
                        .tag(sample.id)
                }
                .onDelete(perform: library.deleteSamples)
            }
            .listStyle(.sidebar)
            .onDrop(of: ["public.file-url"], isTargeted: $isDropTargeted) { providers in
                library.handleDrop(providers: providers)
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .padding(8)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 360)
    }
}

struct SampleRow: View {
    @EnvironmentObject private var library: LibraryStore
    let sample: Sample

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sample.displayName)
                .font(.headline)
            if !sample.tags.isEmpty {
                Text(sample.tags.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background {
            WaveformRowBackground(sample: sample)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task {
            library.requestWaveform(for: sample)
        }
    }
}

struct WaveformRowBackground: View {
    @EnvironmentObject private var library: LibraryStore
    let sample: Sample

    var body: some View {
        ZStack {
            if let image = library.waveform(for: sample) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.35)
            } else {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0.9),
                        Color(nsColor: .controlBackgroundColor).opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct WaveformDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    let sample: Sample

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        WaveformGrid()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    )
                if let image = library.waveform(for: sample) {
                    GeometryReader { geo in
                        let inset: CGFloat = 12
                        let availableWidth = max(0, geo.size.width - inset * 2)
                        ZStack {
                            Image(nsImage: image)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .padding(inset)
                                .foregroundStyle(Color(hue: 0.14, saturation: 1.0, brightness: 1.0))
                                .opacity(1.0)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            if library.playbackSampleID == sample.id && library.playbackProgress > 0 {
                                Image(nsImage: image)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(inset)
                                    .foregroundStyle(Color.gray)
                                    .opacity(0.7)
                                    .mask(
                                        HStack {
                                            Rectangle()
                                                .frame(width: availableWidth * CGFloat(library.playbackProgress))
                                            Spacer()
                                        }
                                        .padding(.leading, inset)
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            }
                        }
                    }
            } else {
                ProgressView()
            }
        }
            waveformAxis
        }
        .task {
            library.requestWaveform(for: sample)
        }
    }

    private var waveformAxis: some View {
        let duration = sample.durationSeconds ?? 0
        let mid = duration / 2
        return VStack(spacing: 4) {
            HStack {
                Text(formatAxisTime(0))
                Spacer()
                Text(formatAxisTime(mid))
                Spacer()
                Text(formatAxisTime(duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: library.playbackSampleID == sample.id ? library.playbackProgress : 0)
                .progressViewStyle(.linear)
        }
    }

    private func formatAxisTime(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remaining = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

struct WaveformGrid: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let columns = 10
            let rows = 4
            Path { path in
                for i in 0...columns {
                    let x = width * CGFloat(i) / CGFloat(columns)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                for j in 0...rows {
                    let y = height * CGFloat(j) / CGFloat(rows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        }
    }
}

enum AudioFormatOption: String, CaseIterable {
    case wav
    case mp3

    var displayName: String {
        rawValue.uppercased()
    }
}

enum WavBitDepthOption: Int, CaseIterable {
    case bit16 = 16
    case bit24 = 24
    case bit32 = 32

    var displayName: String {
        "\(rawValue)-bit"
    }
}

enum WavSampleRateOption: Double, CaseIterable {
    case hz44100 = 44100
    case hz48000 = 48000

    var displayName: String {
        rawValue == 44100 ? "44.1 kHz" : "48 kHz"
    }
}

enum SortKey: String, CaseIterable {
    case name
    case size
    case dateCreated
    case sampleRate
    case bitDepth
    case format
    case length

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        case .dateCreated: return "Date Created"
        case .sampleRate: return "Sample Rate"
        case .bitDepth: return "Bit Depth"
        case .format: return "Format"
        case .length: return "Length"
        }
    }
}

enum SortOrder: String, CaseIterable {
    case ascending
    case descending

    var displayName: String {
        switch self {
        case .ascending: return "Ascending"
        case .descending: return "Descending"
        }
    }
}

struct DetailView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        if library.selection.isEmpty {
            EmptyStateView()
        } else if library.selection.count == 1, let sample = library.selectedSample {
            SampleDetail(sample: sample)
        } else {
            BulkDetailView()
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)

            if library.selection.isEmpty {
                Text("Select a sample to see details.")
                    .foregroundStyle(.secondary)
            } else if library.selection.count == 1, let sample = library.selectedSample {
                InspectorRow(label: "File", value: sample.displayName)
                InspectorRow(label: "Format", value: sample.format?.uppercased() ?? "Unknown")
                InspectorRow(label: "Sample Rate", value: sample.sampleRate.map { "\(Int($0)) Hz" } ?? "Unknown")
                InspectorRow(label: "Bit Depth", value: sample.bitDepth.map { "\($0)-bit" } ?? "Unknown")
                InspectorRow(label: "Length", value: sample.durationSeconds.map { String(format: "%.2f s", $0) } ?? "Unknown")
                InspectorRow(label: "Date Created", value: sample.fileCreated.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Unknown")

                InspectorRow(label: "Tag", value: sample.tags.isEmpty ? "None" : sample.tags.joined(separator: ", "))
            } else {
                Text("\(library.selection.count) samples selected")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 360)
    }
}

struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SampleDetail: View {
    @EnvironmentObject private var library: LibraryStore
    let sample: Sample
    @State private var tagDraft = ""
    @State private var selectedFormat: AudioFormatOption = .wav
    @State private var selectedBitDepth: WavBitDepthOption = .bit16
    @State private var selectedSampleRate: WavSampleRateOption = .hz44100

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sample.displayName)
                    .font(.title2)
                if let duration = sample.durationSeconds {
                    Text(formatDuration(duration))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                Text(sample.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button {
                    library.togglePreview(for: sample)
                } label: {
                    Label(library.isPlaying(sample) ? "Stop" : "Preview", systemImage: library.isPlaying(sample) ? "stop.fill" : "play.fill")
                }

                Button {
                    library.openInExternalEditor(sample)
                } label: {
                    Label("Edit", systemImage: "square.and.arrow.up")
                }

            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.headline)

                if sample.tags.isEmpty {
                    Text("No tags yet.")
                        .foregroundStyle(.secondary)
                } else {
                    TagWrap(tags: sample.tags) { tag in
                        library.removeTag(tag, from: sample)
                    }
                }

                HStack {
                    TextField("Add tags (comma separated)", text: $tagDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        library.addTags(tagDraft, to: sample)
                        tagDraft = ""
                    }
                    .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Divider()
            HStack {
                Text("Selected samples")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    library.removeSelectedSamples()
                } label: {
                    Label("Remove Selected", systemImage: "trash")
                }
                Button(role: .destructive) {
                    library.deleteSelectedFilesFromDisk()
                } label: {
                    Label("Delete Selected", systemImage: "trash.slash")
                }
            }

            HStack(spacing: 12) {
                Text("Convert to")
                    .font(.headline)
                Picker("Format", selection: $selectedFormat) {
                    ForEach(AudioFormatOption.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                if selectedFormat == .wav {
                    Picker("Bit Depth", selection: $selectedBitDepth) {
                        ForEach(WavBitDepthOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Sample Rate", selection: $selectedSampleRate) {
                        ForEach(WavSampleRateOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Button {
                    library.convertSelectedSamples(
                        to: selectedFormat,
                        wavBitDepth: selectedBitDepth,
                        wavSampleRate: selectedSampleRate
                    )
                } label: {
                    Label("Convert Selected", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            WaveformDetailView(sample: sample)
                .frame(maxWidth: .infinity, minHeight: 120)

            Spacer()
        }
        .padding(24)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remaining = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remaining)
    }
}

struct TagWrap: View {
    let tags: [String]
    var onRemove: ((String) -> Void)? = nil

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 80), spacing: 8, alignment: .leading)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagChip(tag: tag, onRemove: onRemove)
            }
        }
    }
}

struct TagChip: View {
    let tag: String
    var onRemove: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.caption)
            if let onRemove {
                Button {
                    onRemove(tag)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove tag")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.7))
        .clipShape(Capsule())
    }
}

struct BulkDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var addTagsDraft = ""
    @State private var removeTagsDraft = ""
    @State private var selectedFormat: AudioFormatOption = .wav
    @State private var selectedBitDepth: WavBitDepthOption = .bit16
    @State private var selectedSampleRate: WavSampleRateOption = .hz44100

    var body: some View {
        let samples = library.selectedSamples
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(samples.count) samples selected")
                    .font(.title2)
                Text(samples.map(\.displayName).sorted().joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Bulk Tags")
                    .font(.headline)

                HStack {
                    TextField("Add tags (comma separated)", text: $addTagsDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Apply") {
                        library.addTags(addTagsDraft, toSamples: samples)
                        addTagsDraft = ""
                    }
                    .disabled(addTagsDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    TextField("Remove tags (comma separated)", text: $removeTagsDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Remove") {
                        library.removeTags(removeTagsDraft, fromSamples: samples)
                        removeTagsDraft = ""
                    }
                    .disabled(removeTagsDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Divider()
            HStack {
                Text("Selected samples")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    library.removeSelectedSamples()
                } label: {
                    Label("Remove Selected", systemImage: "trash")
                }
                Button(role: .destructive) {
                    library.deleteSelectedFilesFromDisk()
                } label: {
                    Label("Delete Selected", systemImage: "trash.slash")
                }
            }

            HStack(spacing: 12) {
                Text("Convert to")
                    .font(.headline)
                Picker("Format", selection: $selectedFormat) {
                    ForEach(AudioFormatOption.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                if selectedFormat == .wav {
                    Picker("Bit Depth", selection: $selectedBitDepth) {
                        ForEach(WavBitDepthOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Sample Rate", selection: $selectedSampleRate) {
                        ForEach(WavSampleRateOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Button {
                    library.convertSelectedSamples(
                        to: selectedFormat,
                        wavBitDepth: selectedBitDepth,
                        wavSampleRate: selectedSampleRate
                    )
                } label: {
                    Label("Convert Selected", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            if !library.lastImportedIDs.isEmpty {
                Divider()
                HStack {
                    Text("Last import")
                        .font(.headline)
                    Spacer()
                    Button(role: .destructive) {
                        library.removeLastImport()
                    } label: {
                        Label("Remove Imported Samples", systemImage: "trash")
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 42))
            Text("Add your first sample")
                .font(.title3)
            Text("Tag samples, preview them instantly, and open in your editor.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AddSampleSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedURL: URL?
    @State private var selectedIsDirectory = false
    @State private var tagsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Sample")
                .font(.title2)

            HStack {
                Text(selectedURL?.path ?? "No file or directory selected")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose File") {
                    pickFile()
                }
                Button("Choose Directory") {
                    pickDirectory()
                }
            }

            TextField("Tags (comma separated)", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Add") {
                    if let url = selectedURL {
                        if selectedIsDirectory {
                            library.addSamplesInBackground(in: url, tags: tagsText)
                        } else {
                            library.addSample(url: url, tags: tagsText)
                        }
                        dismiss()
                    }
                }
                .disabled(selectedURL == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["wav", "aif", "aiff", "mp3", "m4a", "flac", "ogg"]
        if panel.runModal() == .OK {
            selectedURL = panel.url
            selectedIsDirectory = false
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            selectedURL = panel.url
            selectedIsDirectory = true
        }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var samples: [Sample] = []
    @Published var searchText: String = ""
    @Published var selection: Set<Sample.ID> = []
    @Published private var waveformCache: [Sample.ID: NSImage] = [:]
    @Published private(set) var isImporting: Bool = false
    @Published private(set) var importProgress: Double = 0
    @Published private(set) var importStatusText: String = ""
    @Published private(set) var lastImportedIDs: [Sample.ID] = []
    @Published private(set) var isRefreshingMetadata: Bool = false
    @Published private(set) var refreshProgress: Double = 0
    @Published private(set) var refreshStatusText: String = ""
    @Published var sortKey: SortKey = .name
    @Published var sortOrder: SortOrder = .ascending

    private var player: AVPlayer?
    private var currentURL: URL?
    private var playerEndObserver: Any?
    private var playerTimeObserver: Any?
    @Published private(set) var playbackSampleID: Sample.ID?
    @Published private(set) var playbackProgress: Double = 0
    private var waveformInProgress: Set<Sample.ID> = []
    private let supportedExtensions: Set<String> = ["wav", "aif", "aiff", "mp3", "m4a", "flac", "ogg"]

    var filteredSamples: [Sample] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = query.isEmpty ? samples : samples.filter { sample in
            let lower = query.lowercased()
            if sample.displayName.lowercased().contains(lower) { return true }
            if sample.tags.contains(where: { $0.lowercased().contains(lower) }) { return true }
            if let format = sample.format, format.lowercased().contains(lower) { return true }
            if let rate = sample.sampleRate, String(Int(rate)).contains(lower) { return true }
            if let depth = sample.bitDepth, String(depth).contains(lower) { return true }
            if let length = sample.durationSeconds, String(format: "%.2f", length).contains(lower) { return true }
            return false
        }
        return sortSamples(base)
    }

    var selectedSample: Sample? {
        guard selection.count == 1, let selectedID = selection.first else { return nil }
        return samples.first { $0.id == selectedID }
    }

    var selectedSamples: [Sample] {
        samples.filter { selection.contains($0.id) }
    }

    private var libraryURL: URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("Samps", isDirectory: true)
        if !manager.fileExists(atPath: folder.path) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("library.json")
    }

    private var waveformCacheFolder: URL {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("Samps", isDirectory: true)
        if !manager.fileExists(atPath: folder.path) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let cache = folder.appendingPathComponent("waveforms", isDirectory: true)
        if !manager.fileExists(atPath: cache.path) {
            try? manager.createDirectory(at: cache, withIntermediateDirectories: true)
        }
        return cache
    }

    init() {
        load()
    }

    func addSample(url: URL, tags: String) {
        addSamples(urls: [url], tags: tags)
    }

    func addSamples(in directoryURL: URL, tags: String) {
        let urls = collectSampleURLs(in: directoryURL)
        addSamples(urls: urls, tags: tags)
    }

    func addSamples(urls: [URL], tags: String) {
        let cleanedTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let existing = Set(samples.map { $0.url.standardizedFileURL.path })
        var newSamples: [Sample] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            if isDirectory(url: standardized) {
                let nested = collectSampleURLs(in: standardized)
                for nestedURL in nested {
                    let path = nestedURL.standardizedFileURL.path
                    if existing.contains(path) || newSamples.contains(where: { $0.url.standardizedFileURL.path == path }) { continue }
                    if let sample = Self.makeSample(url: nestedURL, tags: cleanedTags) {
                        newSamples.append(sample)
                    }
                }
            } else if isSupportedAudio(url: standardized) {
                let path = standardized.path
                if existing.contains(path) || newSamples.contains(where: { $0.url.standardizedFileURL.path == path }) { continue }
                if let sample = Self.makeSample(url: standardized, tags: cleanedTags) {
                    newSamples.append(sample)
                }
            }
        }

        guard !newSamples.isEmpty else { return }
        samples.insert(contentsOf: newSamples, at: 0)
        selection = Set(newSamples.map(\.id))
        lastImportedIDs = newSamples.map(\.id)
        save()
    }

    func addSamplesInBackground(in directoryURL: URL, tags: String) {
        if isImporting { return }
        isImporting = true
        importProgress = 0
        importStatusText = "Scanning directory..."
        lastImportedIDs = []

        let tagString = tags
        let exts = supportedExtensions
        let existingPaths = Set(samples.map { $0.url.standardizedFileURL.path })

        Task.detached(priority: .utility) { [directoryURL, exts, tagString, existingPaths] in
            let result = Self.collectSampleURLsStatic(in: directoryURL, supportedExtensions: exts)

            await MainActor.run {
                if result.isEmpty {
                    self.importProgress = 1
                    self.importStatusText = "No supported audio files found."
                    self.isImporting = false
                } else {
                    self.importStatusText = "Importing \(result.count) files..."
                }
            }

            if result.isEmpty { return }

            let cleanedTags = tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let total = result.count
            var newSamples: [Sample] = []
            newSamples.reserveCapacity(total)
            var newPaths = Set<String>()

            for (index, url) in result.enumerated() {
                let standardized = url.standardizedFileURL
                let path = standardized.path
                if existingPaths.contains(path) || newPaths.contains(path) { continue }
                if let sample = Self.makeSample(url: standardized, tags: cleanedTags) {
                    newSamples.append(sample)
                    newPaths.insert(path)
                }

                if index % 25 == 0 {
                    let progress = Double(index) / Double(total)
                    await MainActor.run {
                        self.importProgress = progress
                        self.importStatusText = "Importing \(index)/\(total)"
                    }
                }
            }

            await MainActor.run {
                if !newSamples.isEmpty {
                    self.samples.insert(contentsOf: newSamples, at: 0)
                    self.selection = Set(newSamples.map(\.id))
                    self.lastImportedIDs = newSamples.map(\.id)
                    self.save()
                }
                self.importProgress = 1
                self.importStatusText = "Import complete."
                self.isImporting = false
            }
        }
    }

    func removeSelectedSamples() {
        guard !selection.isEmpty else { return }
        let ids = selection
        samples.removeAll { ids.contains($0.id) }
        selection.removeAll()
        save()
    }

    func deleteSelectedFilesFromDisk() {
        guard !selection.isEmpty else { return }
        let ids = selection
        let targets = samples.filter { ids.contains($0.id) }
        for sample in targets {
            try? FileManager.default.removeItem(at: sample.url)
        }
        samples.removeAll { ids.contains($0.id) }
        selection.removeAll()
        save()
    }

    func convertSelectedSamples(
        to format: AudioFormatOption,
        wavBitDepth: WavBitDepthOption,
        wavSampleRate: WavSampleRateOption
    ) {
        let selected = selectedSamples
        guard !selected.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Destination"
        if panel.runModal() != .OK { return }
        guard let destination = panel.url else { return }

        Task.detached(priority: .utility) {
            for sample in selected {
                Self.convertSample(
                    url: sample.url,
                    to: format,
                    destinationDirectory: destination,
                    wavBitDepth: wavBitDepth,
                    wavSampleRate: wavSampleRate
                )
            }
        }
    }

    func refreshMissingMetadata() {
        if isRefreshingMetadata { return }
        isRefreshingMetadata = true
        refreshProgress = 0
        refreshStatusText = "Refreshing metadata..."

        let currentSamples = samples
        Task.detached(priority: .utility) { [currentSamples] in
            var updated: [Sample] = []
            updated.reserveCapacity(currentSamples.count)
            let total = max(1, currentSamples.count)

            for (index, sample) in currentSamples.enumerated() {
                if sample.sampleRate != nil,
                   sample.bitDepth != nil,
                   sample.format != nil,
                   sample.fileCreated != nil,
                   sample.durationSeconds != nil {
                    updated.append(sample)
                } else if let refreshed = Self.makeSample(url: sample.url, tags: sample.tags) {
                    let merged = Sample(
                        id: sample.id,
                        url: refreshed.url,
                        tags: sample.tags,
                        createdAt: sample.createdAt,
                        durationSeconds: refreshed.durationSeconds,
                        sampleRate: refreshed.sampleRate,
                        bitDepth: refreshed.bitDepth,
                        format: refreshed.format,
                        fileCreated: refreshed.fileCreated,
                        fileSizeBytes: refreshed.fileSizeBytes
                    )
                    updated.append(merged)
                } else {
                    updated.append(sample)
                }

                if index % 25 == 0 {
                    let progress = Double(index) / Double(total)
                    await MainActor.run {
                        self.refreshProgress = progress
                        self.refreshStatusText = "Refreshing \(index)/\(total)"
                    }
                }
            }

            await MainActor.run {
                self.samples = updated
                self.save()
                self.isRefreshingMetadata = false
                self.refreshProgress = 1
                self.refreshStatusText = "Refresh complete."
            }
        }
    }

    func removeLastImport() {
        guard !lastImportedIDs.isEmpty else { return }
        let ids = Set(lastImportedIDs)
        samples.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        lastImportedIDs = []
        save()
    }

    func deleteSamples(at offsets: IndexSet) {
        var removed: [Sample.ID] = []
        for index in offsets {
            guard samples.indices.contains(index) else { continue }
            removed.append(samples[index].id)
        }
        samples.remove(atOffsets: offsets)
        selection.subtract(removed)
        save()
    }

    func addTags(_ tags: String, to sample: Sample) {
        let newTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !newTags.isEmpty else { return }
        guard let index = samples.firstIndex(where: { $0.id == sample.id }) else { return }
        var updated = samples[index]
        let combined = Array(Set(updated.tags + newTags)).sorted()
        updated.tags = combined
        samples[index] = updated
        save()
    }

    func addTags(_ tags: String, toSamples samples: [Sample]) {
        let newTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !newTags.isEmpty else { return }
        var updatedSamples = self.samples
        for sample in samples {
            guard let index = updatedSamples.firstIndex(where: { $0.id == sample.id }) else { continue }
            var updated = updatedSamples[index]
            let combined = Array(Set(updated.tags + newTags)).sorted()
            updated.tags = combined
            updatedSamples[index] = updated
        }
        self.samples = updatedSamples
        save()
    }

    func removeTag(_ tag: String, from sample: Sample) {
        guard let index = samples.firstIndex(where: { $0.id == sample.id }) else { return }
        var updated = samples[index]
        updated.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        samples[index] = updated
        save()
    }

    func removeTags(_ tags: String, fromSamples samples: [Sample]) {
        let tagsToRemove = Set(tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { $0.lowercased() })
        guard !tagsToRemove.isEmpty else { return }
        var updatedSamples = self.samples
        for sample in samples {
            guard let index = updatedSamples.firstIndex(where: { $0.id == sample.id }) else { continue }
            var updated = updatedSamples[index]
            updated.tags.removeAll { tagsToRemove.contains($0.lowercased()) }
            updatedSamples[index] = updated
        }
        self.samples = updatedSamples
        save()
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                handled = true
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data else { return }
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                    guard let url else { return }
                    Task { @MainActor in
                        if self.isDirectory(url: url) {
                            self.addSamplesInBackground(in: url, tags: "")
                        } else {
                            self.addSample(url: url, tags: "")
                        }
                    }
                }
            }
        }
        return handled
    }

    func waveform(for sample: Sample) -> NSImage? {
        waveformCache[sample.id]
    }

    func requestWaveform(for sample: Sample) {
        if waveformCache[sample.id] != nil || waveformInProgress.contains(sample.id) { return }
        waveformInProgress.insert(sample.id)
        let sampleID = sample.id
        let sampleURL = sample.url
        let imageSize = CGSize(width: 260, height: 56)
        if let cached = loadWaveformFromDisk(for: sample, size: imageSize) {
            waveformCache[sampleID] = cached
            waveformInProgress.remove(sampleID)
            return
        }
        Task {
            let cgImage = await Task.detached(priority: .utility) {
                Self.renderWaveformCGImage(for: sampleURL, size: imageSize)
            }.value
            if let cgImage {
                let image = NSImage(cgImage: cgImage, size: imageSize)
                self.waveformCache[sampleID] = image
                self.saveWaveformToDisk(image, for: sample, size: imageSize)
            }
            self.waveformInProgress.remove(sampleID)
        }
    }

    func togglePreview(for sample: Sample) {
        if isPlaying(sample) {
            stopPlayer()
            return
        }

        stopPlayer()
        let player = AVPlayer(url: sample.url)
        self.player = player
        self.currentURL = sample.url
        self.playbackSampleID = sample.id
        self.playbackProgress = 0
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopPlayer()
            }
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        playerTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let duration = player.currentItem?.duration.seconds ?? 0
            if duration > 0 {
                Task { @MainActor in
                    self.playbackProgress = min(1, max(0, time.seconds / duration))
                }
            }
        }
        player.play()
    }

    func isPlaying(_ sample: Sample) -> Bool {
        guard let player else { return false }
        return player.timeControlStatus == .playing && currentURL == sample.url
            || (currentURL == sample.url && playbackSampleID == sample.id)
    }

    func openInExternalEditor(_ sample: Sample) {
        NSWorkspace.shared.open(sample.url)
    }

    private func stopPlayer() {
        if let observer = playerEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playerEndObserver = nil
        }
        if let observer = playerTimeObserver, let player {
            player.removeTimeObserver(observer)
            playerTimeObserver = nil
        }
        player?.pause()
        player = nil
        currentURL = nil
        playbackSampleID = nil
        playbackProgress = 0
    }

    private func load() {
        let url = libraryURL
        guard let data = try? Data(contentsOf: url) else {
            samples = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Sample].self, from: data) {
            samples = decoded
        } else {
            samples = []
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(samples) else { return }
        try? data.write(to: libraryURL)
    }

    private func isSupportedAudio(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func isDirectory(url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    private func collectSampleURLs(in directoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            if isSupportedAudio(url: fileURL) {
                urls.append(fileURL)
            }
        }
        return urls
    }

    nonisolated private static func collectSampleURLsStatic(in directoryURL: URL, supportedExtensions: Set<String>) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                urls.append(fileURL)
            }
        }
        return urls
    }

    nonisolated private static func loadDuration(for url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        if duration.isNumeric && duration.seconds > 0 {
            return duration.seconds
        }
        return nil
    }

    nonisolated private static func makeSample(url: URL, tags: [String]) -> Sample? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let duration = loadDuration(for: url)
        let (sampleRate, bitDepth) = loadAudioFormat(for: url)
        let format = url.pathExtension.lowercased()
        let fileCreated = loadFileCreatedDate(for: url)
        let fileSizeBytes = loadFileSize(for: url)
        return Sample(
            id: UUID(),
            url: url,
            tags: tags,
            createdAt: Date(),
            durationSeconds: duration,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            format: format.isEmpty ? nil : format,
            fileCreated: fileCreated,
            fileSizeBytes: fileSizeBytes
        )
    }

    nonisolated private static func loadAudioFormat(for url: URL) -> (Double?, Int?) {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let rate = format.sampleRate
            let depth = Int(format.streamDescription.pointee.mBitsPerChannel)
            return (rate > 0 ? rate : nil, depth > 0 ? depth : nil)
        } catch {
            return (nil, nil)
        }
    }

    nonisolated private static func loadFileCreatedDate(for url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.creationDate] as? Date
    }

    nonisolated private static func loadFileSize(for url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        if let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    }

    private func waveformCachePath(for sample: Sample, size: CGSize) -> URL {
        let key = "\(sample.url.path)|\(sample.fileSizeBytes ?? 0)|\(Int(size.width))x\(Int(size.height))"
        let filename = String(key.hashValue) + ".png"
        return waveformCacheFolder.appendingPathComponent(filename)
    }

    private func loadWaveformFromDisk(for sample: Sample, size: CGSize) -> NSImage? {
        let url = waveformCachePath(for: sample, size: size)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func saveWaveformToDisk(_ image: NSImage, for sample: Sample, size: CGSize) {
        let url = waveformCachePath(for: sample, size: size)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func sortSamples(_ list: [Sample]) -> [Sample] {
        let sorted = list.sorted { lhs, rhs in
            let result: ComparisonResult
            switch sortKey {
            case .name:
                result = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            case .size:
                result = compare(lhs.fileSizeBytes, rhs.fileSizeBytes)
            case .dateCreated:
                result = compare(lhs.fileCreated, rhs.fileCreated)
            case .sampleRate:
                result = compare(lhs.sampleRate, rhs.sampleRate)
            case .bitDepth:
                result = compare(lhs.bitDepth, rhs.bitDepth)
            case .format:
                result = (lhs.format ?? "").localizedCaseInsensitiveCompare(rhs.format ?? "")
            case .length:
                result = compare(lhs.durationSeconds, rhs.durationSeconds)
            }
            if sortOrder == .ascending {
                return result != .orderedDescending
            } else {
                return result == .orderedDescending
            }
        }
        return sorted
    }

    private func compare<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (l?, r?):
            if l == r { return .orderedSame }
            return l < r ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedAscending
        case (_?, nil):
            return .orderedDescending
        }
    }

    nonisolated private static func convertSample(
        url: URL,
        to format: AudioFormatOption,
        destinationDirectory: URL,
        wavBitDepth: WavBitDepthOption,
        wavSampleRate: WavSampleRateOption
    ) {
        do {
            let input = try AVAudioFile(forReading: url)
            let inputFormat = input.processingFormat
            let channels = Int(inputFormat.channelCount)
            let sampleRate = inputFormat.sampleRate
            let baseName = url.deletingPathExtension().lastPathComponent
            let outputURL = destinationDirectory.appendingPathComponent("\(baseName).\(format.rawValue)")
            let settings: [String: Any]
            if format == .wav {
                settings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: wavSampleRate.rawValue,
                    AVNumberOfChannelsKey: channels,
                    AVLinearPCMBitDepthKey: wavBitDepth.rawValue,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
            } else {
                settings = [
                    AVFormatIDKey: kAudioFormatMPEGLayer3,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Variable,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
            }

            let output = try AVAudioFile(forWriting: outputURL, settings: settings)

            let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4096)!
            while true {
                try input.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
            }
        } catch {
            return
        }
    }

    nonisolated private static func renderWaveformCGImage(for url: URL, size: CGSize) -> CGImage? {
        do {
            let file = try AVAudioFile(forReading: url)
            let frameCount = Int(file.length)
            guard frameCount > 0 else { return nil }

            let binCount = max(40, Int(size.width))
            var peaks = [Float](repeating: 0, count: binCount)

            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
            var framesRead = 0

            while framesRead < frameCount {
                let framesToRead = min(Int(buffer.frameCapacity), frameCount - framesRead)
                try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
                guard let data = buffer.floatChannelData else { break }
                let channelCount = Int(buffer.format.channelCount)
                let frameLength = Int(buffer.frameLength)

                for i in 0..<frameLength {
                    var sample: Float = 0
                    for channel in 0..<channelCount {
                        sample += abs(data[channel][i])
                    }
                    sample /= Float(channelCount)
                    let globalIndex = framesRead + i
                    let bin = min(binCount - 1, Int(Double(globalIndex) / Double(frameCount) * Double(binCount)))
                    if sample > peaks[bin] {
                        peaks[bin] = sample
                    }
                }
                framesRead += frameLength
            }

            let maxPeak = peaks.max() ?? 1
            if maxPeak > 0 {
                peaks = peaks.map { $0 / maxPeak }
            }

            let width = max(1, Int(size.width))
            let height = max(1, Int(size.height))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }

            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.75).cgColor)
            context.setLineWidth(1)
            let midY = CGFloat(height) / 2

            for x in 0..<binCount {
                let amplitude = CGFloat(peaks[x]) * (CGFloat(height) * 0.9)
                let y1 = midY - amplitude / 2
                let y2 = midY + amplitude / 2
                let xPos = CGFloat(x) + 0.5
                context.move(to: CGPoint(x: xPos, y: y1))
                context.addLine(to: CGPoint(x: xPos, y: y2))
            }

            context.strokePath()
            return context.makeImage()
        } catch {
            return nil
        }
    }
}

struct Sample: Identifiable, Codable, Hashable {
    let id: UUID
    let url: URL
    var tags: [String]
    let createdAt: Date
    let durationSeconds: Double?
    let sampleRate: Double?
    let bitDepth: Int?
    let format: String?
    let fileCreated: Date?
    let fileSizeBytes: Int64?

    var displayName: String {
        url.lastPathComponent
    }
}
