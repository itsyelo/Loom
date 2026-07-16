import UIKit
import Loom

/// Tab 2 — the lazy `LayoutCache` + prefetch pattern.
///
/// Layouts are computed on demand (prefetch keeps ahead of the scroll;
/// a miss computes synchronously in `heightForRowAt`). This fits content
/// you can't fully pre-compute — search results, unbounded browsing,
/// mixed feeds. For a feed you fully control, prefer the pipeline
/// pattern on Tab 1.
final class LazyCacheViewController: UITableViewController, UITableViewDataSourcePrefetching {

    /// Cache key: exact Hashable identity — the expanded state is part of
    /// the key, so collapsed/expanded results never overwrite each other.
    private struct CellKey: Hashable {
        let postID: String
        let expanded: Bool
    }

    private var contents: [FeedContent] = []
    private let layoutCache = LayoutCache(countLimit: 600)
    private var expandedPostIDs = Set<String>()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lazy Cache"
        tableView.register(FeedCell.self, forCellReuseIdentifier: FeedCell.reuseID)
        tableView.separatorStyle = .none
        tableView.prefetchDataSource = self

        // Attributed strings are still built once per post (off-main) —
        // "lazy" applies to layout calculation, not to content.
        let posts = Post.mockPosts(count: 300)
        DispatchQueue.global(qos: .userInitiated).async {
            let contents = posts.map(FeedContent.init)
            DispatchQueue.main.async {
                self.contents = contents
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - DataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        contents.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 56)
            .insetBy(dx: 12, dy: 6))
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.text = "Lazy LayoutCache + prefetch: layouts compute on demand. "
            + "Fits search results / unbounded browsing. For a feed you fully "
            + "control, prefer the pipeline pattern (Feed tab)."
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let container = UIView()
        container.backgroundColor = .systemBackground
        container.addSubview(label)
        return container
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        56
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FeedCell.reuseID, for: indexPath) as! FeedCell
        let content = contents[indexPath.row]
        let expanded = expandedPostIDs.contains(content.post.id)
        cell.configure(content: content, result: resolveLayout(for: content, expanded: expanded), expanded: expanded)
        return cell
    }

    // MARK: - Delegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let content = contents[indexPath.row]
        let expanded = expandedPostIDs.contains(content.post.id)
        // On a cache miss this calculates synchronously on the main
        // thread — the inherent trade-off of the lazy pattern.
        return resolveLayout(for: content, expanded: expanded).height
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let content = contents[indexPath.row]
        let willExpand = !expandedPostIDs.contains(content.post.id)
        if willExpand {
            expandedPostIDs.insert(content.post.id)
        } else {
            expandedPostIDs.remove(content.post.id)
        }

        // The new state has its own cache key; resolve computes it on
        // first toggle and hits the cache on subsequent toggles.
        let result = resolveLayout(for: content, expanded: willExpand)
        if let cell = tableView.cellForRow(at: indexPath) as? FeedCell {
            cell.configure(content: content, result: result, expanded: willExpand)
        }
        tableView.beginUpdates()
        tableView.endUpdates()
    }

    // MARK: - Prefetching

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        let width = tableView.bounds.width
        let targets: [(FeedContent, Bool)] = indexPaths.compactMap { path in
            guard path.row < contents.count else { return nil }
            let content = contents[path.row]
            return (content, expandedPostIDs.contains(content.post.id))
        }

        DispatchQueue.global(qos: .userInitiated).async { [layoutCache] in
            for (content, expanded) in targets {
                _ = layoutCache.resolve(
                    id: CellKey(postID: content.post.id, expanded: expanded),
                    width: width
                ) {
                    FeedCell.buildLayout(content: content, width: width, expanded: expanded)
                }
            }
        }
    }

    // MARK: - Helpers

    private func resolveLayout(for content: FeedContent, expanded: Bool) -> LayoutResult {
        let width = tableView.bounds.width
        return layoutCache.resolve(
            id: CellKey(postID: content.post.id, expanded: expanded),
            width: width
        ) {
            FeedCell.buildLayout(content: content, width: width, expanded: expanded)
        }
    }

}
