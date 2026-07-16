import UIKit
import Loom
import SDWebImage

final class LinkPreviewCard: UIView {

    let imageView = UIImageView()
    let imageOverlay = UIView()       // gradient overlay on image
    let domainBadgeLabel = UILabel()   // domain badge on top of image
    let titleLabel = UILabel()
    let descLabel = UILabel()
    let domainLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        layer.cornerRadius = 10
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5

        // Semi-transparent gradient overlay at bottom of image
        imageOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)

        // Domain badge floating on the image
        domainBadgeLabel.font = .boldSystemFont(ofSize: 10)
        domainBadgeLabel.textColor = .white
        domainBadgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        domainBadgeLabel.layer.cornerRadius = 4
        domainBadgeLabel.clipsToBounds = true
        domainBadgeLabel.textAlignment = .center

        titleLabel.numberOfLines = 1
        titleLabel.font = .boldSystemFont(ofSize: 14)

        descLabel.numberOfLines = 2
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel

        domainLabel.numberOfLines = 1
        domainLabel.font = .systemFont(ofSize: 12)
        domainLabel.textColor = .tertiaryLabel

        for v in [imageView, imageOverlay, domainBadgeLabel,
                  titleLabel, descLabel, domainLabel] {
            addSubview(v)
        }
    }

    func configure(with preview: LinkPreview) {
        imageView.sd_setImage(with: preview.imageURL)
        domainBadgeLabel.text = "  \(preview.domain)  "
        titleLabel.text = preview.title
        descLabel.text = preview.description
        domainLabel.text = preview.domain
    }

    func prepareForReuse() {
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = nil
    }
}
