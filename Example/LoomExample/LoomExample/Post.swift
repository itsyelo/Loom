import UIKit

// MARK: - Link Preview Model

struct LinkPreview {
    let title: String
    let description: String
    let domain: String
    let imageURL: URL
    let imageHeight: CGFloat
}

// MARK: - Data Model

struct Post {
    let id: String
    let authorName: String
    let avatarURL: URL
    let bodyText: String
    let timeText: String
    let linkPreview: LinkPreview?

    // MARK: - Mock Data

    static func mockPosts(count: Int) -> [Post] {
        let bodies = [
            // Deliberately short: fits within the collapsed 2-line cap, so
            // measureDetails marks it non-expandable (tap does nothing).
            "Short and sweet. 🎉 #brevity",
            "Just had an amazing coffee this morning! ☕ Highly recommend the new place on 5th street. @coffeelover #morningvibes",
            "Working on a new open source project called `Loom` — check out https://github.com/itsyelo/Loom for the source. It's a *background thread* layout engine for iOS. @swiftdev #opensource #iOS",
            "Beautiful sunset today! 🌅 Shot with iPhone, no filters. The colors were *absolutely stunning*. #photography #nofilter #sunset",
            "Has anyone tried the new restaurant downtown? @foodie_mike told me about it. The reviews on https://yelp.com look great but I want to hear from someone who's *actually* been there. Let me know! #foodie #recommendations",
            "Quick tip: use `CTFramesetterCreateWithAttributedString` for thread-safe text measurement on iOS. Much better than `NSAttributedString.boundingRect` which has *historical threading issues*. See https://developer.apple.com/documentation/coretext for details. @iOSDev #swift #coretext",
            "Happy Friday everyone! 🎉 What are your plans for the weekend? I'm planning to work on some #opensource projects and maybe try that new *Italian* place @diana mentioned. #TGIF",
            "Just deployed `v2.0` to production. Zero downtime migration with *50% latency reduction*. The team did an incredible job — @alice @bob @charlie all contributed critical pieces. Read the full write-up at https://engineering.blog/v2-release. #devops #deployment",
            "Reading a great book about *systems design* by @martin_kleppmann. Key takeaway so far: \"Data-intensive applications are fundamentally about making data useful.\" Highly recommend `Designing Data-Intensive Applications`. #books #engineering #systemsdesign",
            "TIL: `Yoga` layout engine supports *CSS Grid* since v3.0, not just Flexbox! This opens up a lot of possibilities for complex layouts. Check https://yogalayout.dev for the docs. @nicklockwood #yoga #layout #css",
            "مرحبًا! تطبيق `Loom` الجديد يدعم الآن RTL تلقائيًا — نفس وصف التخطيط يعمل في *العربية* و*العبرية* دون تغيير الكود. اقرأ المزيد على https://github.com/itsyelo/Loom @ahmed #loom #rtl",
            "Long post incoming... So I've been thinking about the *state of iOS development* in 2026 and there are a few trends that really stand out to me.\n\nFirst, `Swift Concurrency` has completely changed how we think about threading — `async/await`, `actors`, and `Sendable` are now the standard.\n\nSecond, the push toward *declarative UI* continues but UIKit isn't going anywhere. Frameworks like @TextureGroup's `Texture` proved that UIKit can be incredibly performant with the right abstractions.\n\nThird, performance optimization is becoming more important as apps get more complex. Tools like `Instruments`, `MetricKit`, and custom solutions like #Loom help teams stay on top of frame drops.\n\nWhat do you all think? I'd love to hear different perspectives on where things are headed. @swiftlang @apple #iOS #swift #2026 #development"
        ]
        let names = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Hank"]
        let times = ["1m", "5m", "12m", "1h", "3h", "6h", "1d", "2d"]

        // Unsplash avatar photos (different people)
        let avatarPhotos = [
            "photo-1494790108377-be9c29b29330",  // woman
            "photo-1507003211169-0a1dd7228f2d",  // man
            "photo-1517841905240-472988babdf9",  // woman 2
            "photo-1500648767791-00dcc994a43e",  // man 2
            "photo-1438761681033-6461ffad8d80",  // woman 3
            "photo-1472099645785-5658abf4ff4e",  // man 3
            "photo-1544005313-94ddf0286df2",     // woman 4
            "photo-1506794778202-cad84cf45f1d",  // man 4
        ]
        func avatarURL(index: Int) -> URL {
            URL(string: "https://images.unsplash.com/\(avatarPhotos[index % avatarPhotos.count])?w=80&h=80&fit=crop&crop=face")!
        }

        let previews: [LinkPreview?] = [
            nil,
            LinkPreview(
                title: "Loom: Background Layout Engine for iOS",
                description: "A Swift library that uses Yoga to pre-calculate UIView frames on background threads.",
                domain: "github.com",
                imageURL: URL(string: "https://images.unsplash.com/photo-1461749280684-dccba630e2f6?w=700&h=320&fit=crop")!,
                imageHeight: 160
            ),
            nil,
            LinkPreview(
                title: "The Best New Restaurants in Town",
                description: "Our critics pick the top 10 new spots worth visiting this season.",
                domain: "foodie.com",
                imageURL: URL(string: "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=700&h=280&fit=crop")!,
                imageHeight: 140
            ),
            nil,
            nil,
            LinkPreview(
                title: "Zero-Downtime Deployment: A Practical Guide",
                description: "Learn how to deploy without interrupting your users, including blue-green and canary strategies.",
                domain: "engineering.blog",
                imageURL: URL(string: "https://images.unsplash.com/photo-1504639725590-34d0984388bd?w=700&h=240&fit=crop")!,
                imageHeight: 120
            ),
            nil,
            nil,
            nil,
            nil,  // for the Arabic RTL demo post (index 10)
        ]

        return (0..<count).map { i in
            Post(
                id: "post-\(i)",
                authorName: names[i % names.count],
                avatarURL: avatarURL(index: i % names.count),
                bodyText: bodies[i % bodies.count],
                timeText: times[i % times.count],
                linkPreview: previews[i % previews.count]
            )
        }
    }
}
