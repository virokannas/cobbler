//
//  MainView.swift
//  Shared
//
//  Created by Simo Virokannas on 7/16/22.
//

import SwiftUI
import AVKit
import SwiftyXMLParser
import Alamofire

extension String {
    var asDuration: Double {
        let parts = self.split(separator: ":")
        if parts.count == 2 {
            return (Double(parts[0]) ?? 0.0) * 60.0 + (Double(parts[1]) ?? 0.0)
        }
        return 0.0
    }
    
    var asDate: Date {
        let dateStringFormatter = DateFormatter()
        dateStringFormatter.dateFormat = "E, dd MMM yyyy HH:mm:ss Z"
        dateStringFormatter.timeZone = .current
        if let date = dateStringFormatter.date(from: self) {
            return date
        }
        return .now
    }
}

extension Double {
    var asMinSec: String {
        let mins = Int(self / 60.0)
        let secs = Int(self - (Double(mins) * 60.0))
        return "\(mins):\(String(format: "%02d", secs))"
    }
}

struct SongEntry {
    var artist: String = ""
    var song: String = ""
    var artistID: Int = 0
    var songID: Int = 0
    var songDuration: Double = 0.0
    var requester: String = ""
    var playStart: Date = Date.now
    init(_ entry: XML.Accessor) {
        // multiple artists? more than two? meh
        if let artist = entry.artist.text {
            self.artist = artist
        } else if let text1 = entry.artist[0].text, let text2 = entry.artist[1].text {
            self.artist = "\(text1) & \(text2)"
        }
        self.song = entry.song.text ?? "UNKNOWN"
        self.songDuration = (entry.song.attributes["length"] ?? "0:00").asDuration
        self.artistID = Int(entry.artist.attributes["id"] ?? "0") ?? 0
        self.songID = Int(entry.song.attributes["id"] ?? "0") ?? 0
        self.requester = entry.requester.text ?? "UNKNOWN"
        if let pstext = entry.playstart.text {
            self.playStart = pstext.asDate
        }
    }
    
    init() {}
    
    var timeLeft: Double {
        return songDuration - Date.now.timeIntervalSince(playStart)
    }
    
    var songURL: URL {
        return URL(string: "https://scenestream.net/demovibes/song/\(self.songID)/")!
    }

    var artistURL: URL {
        return URL(string: "https://scenestream.net/demovibes/artist/\(self.artistID)/")!
    }

    var progress: Double {
        if self.songDuration == 0.0 {
            return 0.0
        }
        return min(max(1.0 - self.timeLeft / self.songDuration, 0.0), 1.0)
    }
}

class NectaQueue: NSObject, ObservableObject, AVPlayerItemMetadataOutputPushDelegate {
    static private let queueURL = "https://scenestream.net/demovibes/xml/queue/"
    @Published var nowPlaying: SongEntry = SongEntry()
    var runningRefresh: Bool = false
    var lastRefresh: Date = Date.now

    static func load() -> NectaQueue {
        let newQueue = NectaQueue()
        newQueue.runningRefresh = true
        AF.request(NectaQueue.queueURL).responseData {
            response in
            newQueue.runningRefresh = false
            if let data = response.data {
                print(String(data: data, encoding: .utf8)!)
                let xml = XML.parse(data)
                DispatchQueue.main.async {
                    newQueue.objectWillChange.send()
                    newQueue.nowPlaying = SongEntry(xml.playlist.now.entry)
                }
            }
        }
        return newQueue
    }
    
    func runRefresh() {
        if runningRefresh {
            return
        }
        if Date.now.timeIntervalSince(lastRefresh) < 5.0 {
            return
        }
        runningRefresh = true
        lastRefresh = Date.now
        
        AF.request(NectaQueue.queueURL).responseData {
            response in
            self.runningRefresh = false
            if let data = response.data {
                let xml = XML.parse(data)
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.nowPlaying = SongEntry(xml.playlist.now.entry)
                }
            }
        }
    }
}

struct MainView: View {
    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    let timer2 = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State var streamURL: URL = URL(string: "https://scenestream.io/necta48.aac")!
    @State var volume: Float = UserDefaults.standard.value(forKey: "volume") as? Float ?? 75
    var player: AVPlayer = AVPlayer()
    @ObservedObject var queue: NectaQueue = NectaQueue()
    
    init() {
        self.player = AVPlayer(url: streamURL)
        self.queue = NectaQueue.load()
        self.player.volume = (UserDefaults.standard.value(forKey: "volume") as? Float ?? 75) / 100.0
    }
    
    var body: some View {
        VStack() {
            HStack {
                Text(queue.nowPlaying.song).font(.headline)
                Link(destination: queue.nowPlaying.songURL, label: {Text("􀉣")}).font(.headline)
            }
            HStack {
                Text(queue.nowPlaying.artist).font(.subheadline)
                Link(destination: queue.nowPlaying.artistURL, label: {Text("􀉣")}).font(.subheadline)
            }
            Text("requested by: \(queue.nowPlaying.requester)").font(.footnote)
            ProgressView(value: queue.nowPlaying.progress).progressViewStyle(.linear)
            HStack(alignment: .center, spacing: 16) {
                Text(queue.nowPlaying.songDuration.asMinSec).font(.caption)
                HStack(alignment: .center) {
                    Text("􀊡")
                    Slider(value: $volume, in: 0...100) { chg in
                        player.volume = volume / 100.0
                        UserDefaults.standard.set(volume, forKey: "volume")
                    }
                    Text("􀊩")
                }
                Text(queue.nowPlaying.timeLeft.asMinSec).font(.caption)
            }
            VideoPlayer(player: player).onAppear {
                player.play()
            }.frame(height: 0).opacity(0.0)
            .onReceive(timer, perform: { _ in
                // this would _still_ be too often
                //queue.runRefresh()
            }).onReceive(timer2, perform: { _ in
                queue.objectWillChange.send()
                if queue.nowPlaying.timeLeft < 0.0 {
                    queue.runRefresh()
                }
            })
        }
        .padding()
    }
}
