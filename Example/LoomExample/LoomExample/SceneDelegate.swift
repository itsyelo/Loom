import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let feed = FeedPipelineViewController(style: .plain)
        feed.tabBarItem = UITabBarItem(
            title: "Feed", image: UIImage(systemName: "list.bullet.rectangle"), tag: 0
        )

        let lazyCache = LazyCacheViewController(style: .plain)
        lazyCache.tabBarItem = UITabBarItem(
            title: "Lazy Cache", image: UIImage(systemName: "arrow.triangle.2.circlepath"), tag: 1
        )

        let showcase = ShowcaseViewController()
        showcase.tabBarItem = UITabBarItem(
            title: "Showcase", image: UIImage(systemName: "square.grid.2x2"), tag: 2
        )

        let customView = CustomViewViewController()
        customView.tabBarItem = UITabBarItem(
            title: "Custom View", image: UIImage(systemName: "person.crop.square"), tag: 3
        )

        let chat = ChatViewController()
        chat.tabBarItem = UITabBarItem(
            title: "Chat", image: UIImage(systemName: "bubble.left.and.bubble.right"), tag: 4
        )

        let tabBar = UITabBarController()
        tabBar.viewControllers = [feed, lazyCache, showcase, customView, chat].map {
            UINavigationController(rootViewController: $0)
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = tabBar
        window.makeKeyAndVisible()
        self.window = window
    }
}
