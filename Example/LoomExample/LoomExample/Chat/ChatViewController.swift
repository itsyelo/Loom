import UIKit
import Loom

/// Tab 5 — a complex, real-world Loom pipeline consumer: a scrolling chat
/// conversation with three interleaved bubble cell types (text/image/system).
///
/// Mirrors `FeedPipelineViewController`'s pipeline shape (background VM
/// construction, generation-gated publish, `heightForRowAt` as a pure
/// property read) with one deliberate difference: the initial history loads
/// as a single batch instead of chunked appends. In a bottom-anchored chat
/// the newest message is exactly what fills the viewport, so a chunked load
/// would make the visible region "pop in" last, causing a first-screen jump
/// (see findings.md, task 04 planning adjustment). Chunked-load-with-
/// stable-viewport is instead demonstrated by task 07's history-prepend flow.
///
/// A plain `UIViewController` holding its own `UITableView` (not
/// `UITableViewController`) so task 05 can add an input bar pinned to the
/// bottom of `view` alongside the table.
final class ChatViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = ChatInputBar()

    private var items: [ChatMessageVM] = []
    private var direction: LoomDirection = .ltr
    private var pipelineStarted = false
    /// Bumped on every (re)start; guards against a stale background batch
    /// landing after a restart (mirrors `FeedPipelineViewController`).
    private var generation = 0

    // MARK: History Paging State (Task 07)

    /// True from the moment a "load earlier history" fetch is dispatched
    /// until its result (page or nil) has been applied on the main thread.
    /// The sole reentrancy guard for `loadEarlierHistory()` — cleared only
    /// after any resulting prepend's offset compensation has already been
    /// applied, so a `scrollViewDidScroll` fired *synchronously* by our own
    /// `contentOffset` write (see `applyEarlierPage`) can't re-trigger a
    /// second load before this one has finished settling the viewport.
    private var isLoadingEarlier = false
    /// False once `MockChat.earlierPage` has confirmed there's nothing
    /// earlier than the oldest loaded message ("start of conversation").
    /// Drives both the scroll-trigger guard and the top loading header's
    /// lifetime.
    private var hasMoreHistory = true
    /// Spinner shown above row 0 while `hasMoreHistory` is true. Always
    /// animating (no per-fetch start/stop) since it only ever represents
    /// "there's more above" rather than "a fetch is in flight right now" —
    /// removed for good once `hasMoreHistory` flips to false.
    private lazy var loadingHeaderView: UIView = {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        container.autoresizingMask = [.flexibleWidth]
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }()

    private static let earlierPageSize = 60
    /// Trigger the next page a bit before row 0 is actually reached, so the
    /// fetch (background VM construction) has a head start on the user's
    /// scroll before they'd notice a blank gap.
    private static let earlierLoadTriggerOffset: CGFloat = 400

    /// Counter for locally composed ("me") messages, e.g. "local-3". Kept
    /// separate from `MockChat`'s "msg-<n>" ids so a locally sent message can
    /// never collide with a history id.
    private var localMessageCounter = 0
    /// Per-row generation for `replaceItem(id:with:)` — guards against an
    /// older in-flight recompute for the *same* id landing after a newer one
    /// (relevant once task 06 calls this repeatedly for one streaming row).
    private var replaceGenerations: [String: Int] = [:]

    // MARK: Bot Reply State (Task 06)

    /// Whether the typing-indicator row is currently in the table. This is
    /// the *only* row that isn't backed by a `ChatMessageVM` — see
    /// `TypingIndicatorCell`'s doc comment for why it stays outside the
    /// pipeline. It is always the last row when visible.
    private var isTypingIndicatorVisible = false
    /// Counter for bot reply message ids, e.g. "bot-3". Separate from both
    /// `localMessageCounter`'s "local-<n>" space and `MockChat`'s "msg-<n>"
    /// history space.
    private var botMessageCounter = 0
    /// True from the moment the typing indicator appears until the current
    /// streaming reply finishes landing. Guards against two replies
    /// visually overlapping if the user sends again while one is in flight.
    private var isBotReplying = false
    /// User messages awaiting a bot reply, queued up if `isBotReplying` was
    /// already true when they became eligible (their `.read` flip landed).
    private var botReplyQueue: [ChatMessage] = []
    /// The current streaming reply's tick timer. At most one is ever
    /// running at a time (`isBotReplying` serializes replies), so a single
    /// property is enough — no per-reply bookkeeping needed.
    private var streamTimer: Timer?

    private static let readAckDelay: TimeInterval = 1.4
    private static let preStreamIndicatorDelay: TimeInterval = 1.2
    private static let streamTickInterval: TimeInterval = 0.1

    /// `(tableView.bounds.height, isNearBottom())` captured at the end of the
    /// previous `viewDidLayoutSubviews` pass. Used to detect a
    /// keyboard-driven height change and decide whether to re-pin the
    /// viewport to the bottom — see `trackNearBottomAcrossLayout()`.
    private var lastNearBottomCheck: (height: CGFloat, nearBottom: Bool)?

    deinit {
        // Not strictly required — `replaceItem`'s id lookup and generation
        // check already make a late tick land harmlessly as a no-op if this
        // controller is gone — but invalidating here means the timer stops
        // firing immediately instead of ticking a few more times into the
        // void.
        streamTimer?.invalidate()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // `navigationItem.title`, not `title` — the plain `title` setter also
        // propagates to `tabBarItem.title`, clobbering the "Chat" tab label
        // set in SceneDelegate.
        navigationItem.title = "Nova"
        view.backgroundColor = .systemBackground
        setupInputBar()
        setupTableView()

        #if DEBUG
        ChatMessageVM.debugSmokeTest()
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        trackNearBottomAcrossLayout()

        // Kick off once the real width is known — same timing as
        // `FeedPipelineViewController`. Direction is resolved on the main
        // thread here; the pipeline itself runs off-main.
        guard !pipelineStarted, view.bounds.width > 0 else { return }
        pipelineStarted = true
        direction = Loom.systemDirection
        loadInitialHistory()
    }

    // MARK: - Table View Setup

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        // Real row heights are always known before a row reaches `items`;
        // disabling estimation keeps `contentSize` exact, which is what
        // makes the bottom-anchoring (and, later, prepend offset
        // compensation) reliable.
        tableView.estimatedRowHeight = 0
        tableView.keyboardDismissMode = .interactive
        // Breathing room between the last bubble and the input bar when
        // resting at the bottom — without it the bar's top hairline sits
        // directly against the last row's edge.
        tableView.contentInset.bottom = 8
        tableView.register(ChatTextCell.self, forCellReuseIdentifier: ChatTextCell.reuseID)
        tableView.register(ChatImageCell.self, forCellReuseIdentifier: ChatImageCell.reuseID)
        tableView.register(ChatSystemCell.self, forCellReuseIdentifier: ChatSystemCell.reuseID)
        tableView.register(TypingIndicatorCell.self, forCellReuseIdentifier: TypingIndicatorCell.reuseID)
        // Present from the start — `hasMoreHistory` is true before the
        // initial load even runs, and there's always at least one earlier
        // page in this demo's ~600-message mock timeline.
        tableView.tableHeaderView = loadingHeaderView

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Pinned to the input bar's top, not `view.bottomAnchor` — the
            // seam task 04 left for this (see findings.md).
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),
        ])
    }

    // MARK: - Input Bar Setup

    private func setupInputBar() {
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.onSend = { [weak self] text in
            self?.send(text: text)
        }
        view.addSubview(inputBar)
        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // `keyboardLayoutGuide.topAnchor` tracks the keyboard's top edge
            // when visible (including interactive dismiss) and coincides
            // with `view.safeAreaLayoutGuide.bottomAnchor` when the keyboard
            // is hidden — that's what keeps the bar off the home indicator
            // with no separate safe-area handling needed here.
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
    }

    // MARK: - Pipeline

    /// Background-assemble the most recent ~80 messages into VMs, then
    /// publish once and land on the bottom row with no animation. See the
    /// class doc comment / findings.md for why this isn't chunked like
    /// `FeedPipelineViewController`.
    private func loadInitialHistory() {
        generation += 1
        let gen = generation
        let width = tableView.bounds.width
        let direction = self.direction
        let history = MockChat.initialHistory(count: 80)

        DispatchQueue.global(qos: .userInitiated).async {
            let vms = history.map { ChatMessageVM(message: $0, width: width, direction: direction) }
            DispatchQueue.main.async {
                // A restart (e.g. a future direction toggle) bumped
                // `generation` again while this batch was in flight — drop it.
                guard gen == self.generation else { return }
                self.items = vms
                self.tableView.reloadData()
                self.scrollToBottom(animated: false)
            }
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard !items.isEmpty else { return }
        let lastRow = IndexPath(row: items.count - 1, section: 0)
        tableView.scrollToRow(at: lastRow, at: .bottom, animated: animated)
    }

    /// Whether the visible viewport currently reaches (within `threshold`
    /// points of) the bottom of the content. Empty table never counts as
    /// "near bottom" — that would make the very first keyboard-driven layout
    /// pass (before `loadInitialHistory` has published anything) spuriously
    /// trigger a scroll.
    private func isNearBottom(threshold: CGFloat = 60) -> Bool {
        guard !items.isEmpty else { return false }
        let visibleBottom = tableView.contentOffset.y + tableView.bounds.height
        return visibleBottom >= tableView.contentSize.height - threshold
    }

    /// Keeps the viewport pinned to the bottom across a keyboard-driven
    /// resize of `tableView` (its bottom is pinned to the input bar, whose
    /// own bottom follows `keyboardLayoutGuide`, so keyboard show/hide
    /// changes `tableView.bounds.height` without changing `contentSize`).
    ///
    /// The key subtlety: whether to re-pin has to be decided using
    /// "was the viewport at the bottom *before* the height changed", not
    /// after — by the time this runs, the resize has already happened. So
    /// each pass first checks the near-bottom flag captured at the *end of
    /// the previous* pass (when the old height was still current), then
    /// records a fresh flag for the next pass.
    private func trackNearBottomAcrossLayout() {
        let currentHeight = tableView.bounds.height
        defer { lastNearBottomCheck = (currentHeight, isNearBottom()) }

        guard let last = lastNearBottomCheck, last.height != currentHeight else { return }
        if last.nearBottom {
            scrollToBottom(animated: false)
        }
    }

    // MARK: - History Paging (Task 07)

    /// Fetches up to `earlierPageSize` messages immediately before the
    /// oldest currently-loaded one and prepends them. Guarded against
    /// reentrancy by `isLoadingEarlier` and against a stale result landing
    /// after an unrelated full-pipeline restart by capturing `generation`
    /// up front — the same field `loadInitialHistory` bumps, since a
    /// restart invalidates an in-flight earlier-page fetch just as much as
    /// it would an in-flight initial load.
    private func loadEarlierHistory() {
        guard !isLoadingEarlier, hasMoreHistory, let cursorID = items.first?.id else { return }
        isLoadingEarlier = true

        let gen = generation
        let width = tableView.bounds.width
        let direction = self.direction
        let pageSize = Self.earlierPageSize

        DispatchQueue.global(qos: .userInitiated).async {
            let page = MockChat.earlierPage(before: cursorID, limit: pageSize)
            // `page?.first?.id == MockChat.fullTimeline.first?.id` (rather
            // than `page.count < pageSize`) is what actually detects "this
            // page reaches the start of the conversation" — a page can
            // legitimately be exactly `pageSize` long *and* still be the
            // final one, if the remaining history happens to be an exact
            // multiple of the page size.
            let isFinalPage = page?.first?.id == MockChat.fullTimeline.first?.id
            let vms = page?.map { ChatMessageVM(message: $0, width: width, direction: direction) }
            DispatchQueue.main.async { [weak self] in
                self?.finishLoadingEarlier(vms: vms, isFinalPage: isFinalPage, generationAtStart: gen)
            }
        }
    }

    /// Applies an earlier-page fetch's result on the main thread. Order of
    /// operations matters: `isLoadingEarlier` is only cleared *after* any
    /// resulting prepend has fully applied its `contentOffset` compensation
    /// (see `applyEarlierPage`), so a `scrollViewDidScroll` fired
    /// synchronously by that very offset write can't reenter
    /// `loadEarlierHistory` mid-update.
    private func finishLoadingEarlier(vms: [ChatMessageVM]?, isFinalPage: Bool, generationAtStart: Int) {
        // A full-pipeline restart happened while this fetch was in flight
        // (mirrors `loadInitialHistory`'s own generation check) — the
        // `items` this page would prepend onto no longer exist.
        guard generationAtStart == generation else { return }

        defer { isLoadingEarlier = false }

        guard let vms else {
            // `MockChat.earlierPage` returned nil: the cursor was already
            // the conversation's first message. Not reachable in practice
            // today (see `isFinalPage` above, which catches this one fetch
            // earlier), but handled defensively in case paging semantics
            // change.
            hasMoreHistory = false
            removeLoadingHeader()
            return
        }
        if isFinalPage {
            hasMoreHistory = false
        }
        applyEarlierPage(vms, isFinalPage: isFinalPage)
    }

    /// Prepends `vms` to `items` and compensates `tableView.contentOffset`
    /// so the viewport's visible pixels don't shift by even one point.
    ///
    /// This is only exact because every VM's height is a *known* property,
    /// not a UITableView-estimated guess: with `estimatedRowHeight = 0`
    /// (set in `setupTableView`), `contentSize` grows by precisely the sum
    /// of the new rows' heights the moment `reloadData()` returns — there's
    /// no later "correction" pass once real heights get measured, which is
    /// exactly what causes the classic visible jump/flicker in the
    /// estimated-height + prepend pattern. Because pipeline VMs compute
    /// their full layout *before* they ever reach `items`, this sum is
    /// knowable up front, so the compensating `contentOffset` write can
    /// land in the very same run-loop turn as the data change — this is the
    /// pipeline paradigm's payoff for this feature specifically.
    private func applyEarlierPage(_ vms: [ChatMessageVM], isFinalPage: Bool) {
        let headerHeight = isFinalPage ? loadingHeaderView.bounds.height : 0
        let addedHeight = vms.reduce(CGFloat(0)) { $0 + $1.height }
        let delta = addedHeight - headerHeight

        UIView.performWithoutAnimation {
            if isFinalPage {
                tableView.tableHeaderView = nil
            }
            items.insert(contentsOf: vms, at: 0)
            // reloadData() first so contentSize already reflects both the
            // new rows and (if applicable) the removed header, then the
            // offset write lands in the same turn — no intermediate frame
            // where the two are out of sync.
            tableView.reloadData()
            tableView.contentOffset.y += delta
        }
    }

    /// Removes the top spinner without prepending anything (the "nil page"
    /// path in `finishLoadingEarlier`) — still needs an offset compensation
    /// since removing 44pt from the top of `contentSize` would otherwise
    /// shift the viewport up by 44pt.
    private func removeLoadingHeader() {
        let headerHeight = loadingHeaderView.bounds.height
        UIView.performWithoutAnimation {
            tableView.tableHeaderView = nil
            tableView.contentOffset.y -= headerHeight
        }
    }

    // MARK: - Sending

    /// Trims and, if non-empty, sends a new "me" message: builds the
    /// `ChatMessageVM` (attributed strings + `LayoutResult`) off-main, then
    /// appends it and scrolls to bottom in one atomic main-thread hop — the
    /// row never appears as a placeholder before its layout is ready.
    private func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        localMessageCounter += 1
        let message = ChatMessage(
            id: "local-\(localMessageCounter)",
            sender: MockChat.me,
            timestamp: Date(),
            kind: .text(trimmed),
            status: .sending
        )

        let width = tableView.bounds.width
        let direction = self.direction
        DispatchQueue.global(qos: .userInitiated).async {
            let vm = ChatMessageVM(message: message, width: width, direction: direction)
            DispatchQueue.main.async { [weak self] in
                self?.appendSentMessage(vm, message: message)
            }
        }
    }

    private func appendSentMessage(_ vm: ChatMessageVM, message: ChatMessage) {
        let newIndex = items.count
        items.append(vm)
        tableView.insertRows(at: [IndexPath(row: newIndex, section: 0)], with: .automatic)
        scrollToBottom(animated: true)
        simulateDelivery(for: message)
        scheduleBotReply(to: message)
    }

    /// Fake "delivered" ack ~0.8s after sending: flips `.sending` → `.sent`
    /// and routes the change through `replaceItem(id:with:)`.
    private func simulateDelivery(for message: ChatMessage) {
        var delivered = message
        delivered.status = .sent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.replaceItem(id: delivered.id, with: delivered)
        }
    }

    /// Generic single-row atomic replace: rebuilds the `ChatMessageVM` (new
    /// content + freshly computed layout) off-main for `newMessage`, then
    /// swaps it into `items` and reloads just that row on the main thread —
    /// never a partial update where content and layout could disagree.
    ///
    /// Reusable entry point (task 06's streaming reply ticks call this
    /// repeatedly for one row), so it guards against two races:
    /// - **out-of-order completion for the same id** — a per-id generation
    ///   counter drops a stale recompute that finishes after a newer one for
    ///   the same message was already requested;
    /// - **the row no longer existing** — e.g. a full pipeline reload
    ///   happened while this recompute was in flight; the id is looked up by
    ///   value in `items` and the update is dropped if it's gone, rather than
    ///   assuming a stale index is still valid.
    ///
    /// `pinToBottomIfNeeded` covers task 06's streaming-reply follow: when
    /// `true`, the near-bottom check runs *before* the background rebuild
    /// starts (captured by the caller, at the moment the tick fires — see
    /// `beginStreamTimer`) so "should this update re-pin the viewport" is
    /// always decided from the state right before this particular update,
    /// never from whatever the viewport happens to be after the row grew.
    private func replaceItem(id: String, with newMessage: ChatMessage, pinToBottomIfNeeded: Bool = false) {
        replaceGenerations[id, default: 0] += 1
        let gen = replaceGenerations[id]!

        let width = tableView.bounds.width
        let direction = self.direction
        DispatchQueue.global(qos: .userInitiated).async {
            let vm = ChatMessageVM(message: newMessage, width: width, direction: direction)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.replaceGenerations[id] == gen else { return }
                guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[index] = vm
                let indexPath = IndexPath(row: index, section: 0)
                // Reconfigure the already-visible cell directly (bypassing
                // dequeue/reload) for instant content updates, then an empty
                // `beginUpdates`/`endUpdates` batch to make UIKit re-query
                // every visible row's height (`items` already holds the new
                // value) — cheaper than `reloadRows` at ~10Hz since it never
                // tears down and rebuilds the cell just to change its text.
                self.reconfigureVisibleCell(at: indexPath, with: vm)
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
                if pinToBottomIfNeeded {
                    self.scrollToBottom(animated: false)
                }
            }
        }
    }

    /// Reconfigures the cell at `indexPath` in place with `vm`'s fresh
    /// content, if that row currently has a live (on-screen) cell. A no-op
    /// when the row isn't visible — the next `cellForRowAt` call will read
    /// `items[indexPath.row]` (already updated by the caller) and configure
    /// correctly from scratch, so there's nothing stale left behind.
    private func reconfigureVisibleCell(at indexPath: IndexPath, with vm: ChatMessageVM) {
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        switch vm.kind {
        case .text:
            (cell as? ChatTextCell)?.configure(vm: vm)
        case .image:
            (cell as? ChatImageCell)?.configure(vm: vm)
        case .system:
            (cell as? ChatSystemCell)?.configure(vm: vm)
        }
    }

    // MARK: - Typing Indicator (Task 06)

    /// Inserts/deletes the indicator as the table's last row (`items.count`),
    /// via `performBatchUpdates` so the row-count change animates like any
    /// other insert/delete. The near-bottom check is captured *before* the
    /// update starts, since the update itself changes `contentSize`.
    private func setTypingIndicator(visible: Bool) {
        guard visible != isTypingIndicatorVisible else { return }
        let wasNearBottom = isNearBottom()
        let row = items.count
        tableView.performBatchUpdates {
            isTypingIndicatorVisible = visible
            if visible {
                tableView.insertRows(at: [IndexPath(row: row, section: 0)], with: .fade)
            } else {
                tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .fade)
            }
        } completion: { [weak self] _ in
            guard let self, wasNearBottom else { return }
            self.scrollToBottom(animated: true)
        }
    }

    /// Atomically swaps the indicator row for the newly-started bot message
    /// row — one `performBatchUpdates` doing a delete (indicator) + insert
    /// (bot row) at the same index, so the table never shows an interim
    /// state with neither (or both) present.
    private func replaceIndicatorWithBotMessage(_ vm: ChatMessageVM) {
        let wasNearBottom = isNearBottom()
        let row = items.count
        tableView.performBatchUpdates {
            isTypingIndicatorVisible = false
            items.append(vm)
            tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .fade)
            tableView.insertRows(at: [IndexPath(row: row, section: 0)], with: .fade)
        } completion: { [weak self] _ in
            guard let self, wasNearBottom else { return }
            self.scrollToBottom(animated: true)
        }
    }

    // MARK: - Bot Reply Chain (Task 06)

    /// Queues the bot's reply to a just-sent "me" message once it's eligible
    /// to be "read": scheduled to fire strictly after `simulateDelivery`'s
    /// `.sent` ack (`readAckDelay` > the 0.8s used there) rather than the
    /// independent "~0.6s from send" the task sketch describes, so the
    /// receipt glyph only ever advances (sending -> sent -> read) and can
    /// never visibly regress if the two timers landed out of order.
    private func scheduleBotReply(to message: ChatMessage) {
        guard case .text = message.kind else { return }
        var read = message
        read.status = .read
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readAckDelay) { [weak self] in
            guard let self else { return }
            self.replaceItem(id: read.id, with: read)
            self.botReplyQueue.append(read)
            self.startNextBotReplyIfIdle()
        }
    }

    /// Pulls the next queued reply (if any) and starts its indicator ->
    /// stream sequence, provided no reply is already in flight. Called both
    /// when a new reply becomes eligible and when the previous stream
    /// finishes, so a reply sent while one was already streaming gets
    /// picked up automatically once the current one lands.
    private func startNextBotReplyIfIdle() {
        guard !isBotReplying, !botReplyQueue.isEmpty else { return }
        isBotReplying = true
        let userMessage = botReplyQueue.removeFirst()
        setTypingIndicator(visible: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.preStreamIndicatorDelay) { [weak self] in
            self?.streamReply(to: userMessage)
        }
    }

    /// Starts streaming the bot's canned reply to `userMessage`: picks the
    /// deterministic reply text + chunk sequence from `BotScript`, swaps the
    /// indicator for a new bot message row seeded with the first chunk, then
    /// hands off to `beginStreamTimer` for the remaining chunks.
    private func streamReply(to userMessage: ChatMessage) {
        guard case .text(let userText) = userMessage.kind else {
            setTypingIndicator(visible: false)
            finishBotReply()
            return
        }
        let chunks = BotScript.chunks(of: BotScript.reply(to: userText))
        guard let firstChunk = chunks.first else {
            setTypingIndicator(visible: false)
            finishBotReply()
            return
        }

        botMessageCounter += 1
        let botID = "bot-\(botMessageCounter)"
        let firstText = firstChunk
        let firstMessage = ChatMessage(id: botID, sender: MockChat.bot, timestamp: Date(), kind: .text(firstText), status: .sent)

        let width = tableView.bounds.width
        let direction = self.direction
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let vm = ChatMessageVM(message: firstMessage, width: width, direction: direction)
            DispatchQueue.main.async {
                self.replaceIndicatorWithBotMessage(vm)
                self.beginStreamTimer(botID: botID, remainingChunks: Array(chunks.dropFirst()), accumulatedText: firstText)
            }
        }
    }

    /// Drives the remaining chunks on a ~10Hz main-thread timer: each tick
    /// appends 1-2 chunks to the accumulated text and pushes the result
    /// through `replaceItem` (background attr + layout rebuild, atomic
    /// main-hop publish — the same discipline as every other row update in
    /// this controller, just at high frequency). Stops itself once the
    /// chunk queue is empty.
    private func beginStreamTimer(botID: String, remainingChunks: [String], accumulatedText: String) {
        var pendingChunks = remainingChunks
        var text = accumulatedText

        streamTimer?.invalidate()
        streamTimer = Timer.scheduledTimer(withTimeInterval: Self.streamTickInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard !pendingChunks.isEmpty else {
                timer.invalidate()
                self.streamTimer = nil
                self.finishBotReply()
                return
            }

            let chunksThisTick = min(2, pendingChunks.count)
            text += pendingChunks.prefix(chunksThisTick).joined()
            pendingChunks.removeFirst(chunksThisTick)

            let wasNearBottom = self.isNearBottom()
            let message = ChatMessage(id: botID, sender: MockChat.bot, timestamp: Date(), kind: .text(text), status: .sent)
            self.replaceItem(id: botID, with: message, pinToBottomIfNeeded: wasNearBottom)
        }
    }

    /// Marks the current reply as landed and immediately checks for a
    /// queued follow-up (from the user sending again mid-stream).
    private func finishBotReply() {
        isBotReplying = false
        startNextBotReplyIfIdle()
    }
}

// MARK: - UITableViewDataSource

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // The typing indicator is never part of `items` (see
        // `TypingIndicatorCell`'s doc comment) — it's always exactly one
        // extra row, tacked onto the end, when visible.
        items.count + (isTypingIndicatorVisible ? 1 : 0)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isTypingIndicatorVisible, indexPath.row == items.count {
            return tableView.dequeueReusableCell(withIdentifier: TypingIndicatorCell.reuseID, for: indexPath) as! TypingIndicatorCell
        }
        let vm = items[indexPath.row]
        switch vm.kind {
        case .text:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatTextCell.reuseID, for: indexPath) as! ChatTextCell
            cell.configure(vm: vm)
            return cell
        case .image:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatImageCell.reuseID, for: indexPath) as! ChatImageCell
            cell.configure(vm: vm)
            return cell
        case .system:
            let cell = tableView.dequeueReusableCell(withIdentifier: ChatSystemCell.reuseID, for: indexPath) as! ChatSystemCell
            cell.configure(vm: vm)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension ChatViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // The indicator row returns a compile-time constant — no view
        // model, no measurement, so still a pure property read.
        if isTypingIndicatorVisible, indexPath.row == items.count {
            return TypingIndicatorCell.rowHeight
        }
        // Pure property read — the pipeline computed every row's layout
        // before it ever reached `items`, so a miss is structurally
        // impossible (mirrors `FeedPipelineViewController`).
        return items[indexPath.row].height
    }

    /// Triggers the next earlier-history page a bit before the user
    /// actually reaches row 0. `!items.isEmpty` doubles as the "initial
    /// load has landed" guard — `items` is empty until `loadInitialHistory`
    /// publishes its first batch, so a layout pass that fires before then
    /// can't spuriously kick off a paging fetch.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard hasMoreHistory, !isLoadingEarlier, !items.isEmpty else { return }
        guard scrollView.contentOffset.y < Self.earlierLoadTriggerOffset else { return }
        loadEarlierHistory()
    }
}
