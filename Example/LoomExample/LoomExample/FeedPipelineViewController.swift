import UIKit
import Loom

/// Tab 1 — the recommended pattern for large feeds ("Feed List Pipeline"
/// in the Loom docs): view models that own their `LayoutResult`s are
/// assembled entirely on a background thread and published in chunks.
///
/// Compare with `LazyCacheViewController` (Tab 2): here `heightForRowAt`
/// is a plain property read — no cache, no miss, no main-thread layout,
/// ever. Expanding a post costs zero calculation because both states were
/// pre-computed in the pipeline.
final class FeedPipelineViewController: UITableViewController {

    private let posts = Post.mockPosts(count: 1000)
    private var items: [FeedItemVM] = []

    private var direction: LoomDirection = .ltr
    private var pipelineStarted = false
    /// Bumped on every (re)start; stale pipeline chunks are dropped.
    private var generation = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Feed"
        tableView.register(FeedCell.self, forCellReuseIdentifier: FeedCell.reuseID)
        tableView.separatorStyle = .none
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "→ RTL", style: .plain, target: self, action: #selector(toggleDirection)
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Kick off once the real width is known. Resolve the direction on
        // the main thread here; the pipeline itself runs off-main.
        guard !pipelineStarted, view.bounds.width > 0 else { return }
        pipelineStarted = true
        direction = Loom.systemDirection
        startPipeline()
    }

    // MARK: - Pipeline

    /// fetch → build attributed strings → calculate both states → publish.
    /// Rows never reach the data source without their layouts, so a miss
    /// is structurally impossible. Chunked publishing keeps the first
    /// screen from waiting on the full page.
    private func startPipeline() {
        generation += 1
        let gen = generation
        let width = tableView.bounds.width
        let direction = self.direction
        let posts = self.posts

        items = []
        tableView.reloadData()
        updateTitle()

        DispatchQueue.global(qos: .userInitiated).async {
            let chunkSize = 50
            var chunk: [FeedItemVM] = []
            chunk.reserveCapacity(chunkSize)

            for post in posts {
                chunk.append(FeedItemVM(post: post, width: width, direction: direction))
                if chunk.count == chunkSize {
                    self.publish(chunk, generation: gen)
                    chunk = []
                }
            }
            if !chunk.isEmpty {
                self.publish(chunk, generation: gen)
            }
        }
    }

    private func publish(_ chunk: [FeedItemVM], generation: Int) {
        DispatchQueue.main.async {
            // A direction toggle restarted the pipeline — drop stale chunks.
            guard generation == self.generation else { return }
            let start = self.items.count
            self.items.append(contentsOf: chunk)
            let paths = (start..<self.items.count).map { IndexPath(row: $0, section: 0) }
            self.tableView.insertRows(at: paths, with: .none)
            self.updateTitle()
        }
    }

    private func updateTitle() {
        title = items.count < posts.count ? "Feed (\(items.count)/\(posts.count))" : "Feed"
    }

    // MARK: - DataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FeedCell.reuseID, for: indexPath) as! FeedCell
        let vm = items[indexPath.row]
        cell.configure(content: vm.content, result: vm.layout, expanded: vm.isExpanded)
        return cell
    }

    // MARK: - Delegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // The whole point: a property read. Never a miss, never a calculation.
        items[indexPath.row].layout.height
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Posts whose body fits in 2 lines have nothing to expand —
        // measureDetails decided this during the pipeline.
        guard items[indexPath.row].isExpandable else { return }

        // Both states were pre-computed in the pipeline — toggling is a
        // zero-calculation state switch.
        items[indexPath.row].isExpanded.toggle()
        let vm = items[indexPath.row]

        if let cell = tableView.cellForRow(at: indexPath) as? FeedCell {
            cell.configure(content: vm.content, result: vm.layout, expanded: vm.isExpanded)
        }
        tableView.beginUpdates()
        tableView.endUpdates()
    }

    // MARK: - Direction toggle (a "whole-world invalidation" event)

    /// Direction changes make every stored layout stale — the standard
    /// handling is to re-run the pipeline at the new direction. The list
    /// clears and repopulates in chunks; a real app could keep showing
    /// the old frames until the first new chunk lands.
    @objc private func toggleDirection() {
        direction = (direction == .rtl) ? .ltr : .rtl
        navigationItem.rightBarButtonItem?.title = (direction == .rtl) ? "← LTR" : "→ RTL"
        startPipeline()
    }
}
