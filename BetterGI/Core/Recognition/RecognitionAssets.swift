//
//  RecognitionAssets.swift
//  BetterGI
//
//  Created by 鸢汐 on 2026/11/19.
//

import Foundation
import opencv2

nonisolated enum RecognitionAssetError: LocalizedError {
    case missingFile(String)
    case invalidConfiguration(String, reason: String)
    case missingObject(String, feature: String)
    case missingRegion(String, feature: String)
    case unreadableTemplate(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let path):
            return "缺少资源文件 \(path)"
        case .invalidConfiguration(let path, let reason):
            return "\(path) 格式有误：\(reason)"
        case .missingObject(let name, let feature):
            return "\(RecognitionAssets.rootDirectory)/\(feature)/Recognition.json 中没有识别对象「\(name)」"
        case .missingRegion(let name, let feature):
            return "\(RecognitionAssets.rootDirectory)/\(feature)/Recognition.json 中的「\(name)」缺少 roi"
        case .unreadableTemplate(let path):
            return "无法读取模板图 \(path)"
        }
    }
}

/// Recognition.json 中的一个模板匹配对象。
nonisolated struct TemplateAsset: @unchecked Sendable {
    let name: String
    /// 1080p 下的灰度模板（CV_8UC1）
    let template: Mat
    /// 搜索区域；为空时由调用方按上下文决定（例如设置图标跟随拾取键的位置）
    let region: RegionExpression?

    var width: Int { Int(template.cols()) }
    var height: Int { Int(template.rows()) }
}

nonisolated enum RecognitionAssets {
    /// App 资源目录下存放识别资源的文件夹
    static let rootDirectory = "Resources"

    nonisolated private struct Configuration: Decodable {
        struct Object: Decodable {
            let type: String
            let template: String?
            let roi: String?
        }

        let objects: [String: Object]
    }

    /// 加载 `feature` 下所有模板匹配对象。
    static func load(feature: String, bundle: Bundle = .main) throws -> [String: TemplateAsset] {
        let featureDirectory = "\(rootDirectory)/\(feature)"
        let templateDirectory = "\(featureDirectory)/1920x1080"

        let configPath = "\(featureDirectory)/Recognition.json"
        guard let configURL = resourceURL(in: bundle, fileName: "Recognition.json", subdirectory: featureDirectory) else {
            throw RecognitionAssetError.missingFile(configPath)
        }

        let configuration: Configuration
        do {
            configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
        } catch {
            throw RecognitionAssetError.invalidConfiguration(configPath, reason: error.localizedDescription)
        }

        var assets: [String: TemplateAsset] = [:]
        for (name, object) in configuration.objects where object.type == "TemplateMatch" {
            guard let fileName = object.template else { continue }

            let templatePath = "\(templateDirectory)/\(fileName)"
            guard let url = resourceURL(in: bundle, fileName: fileName, subdirectory: templateDirectory) else {
                throw RecognitionAssetError.missingFile(templatePath)
            }

            let region: RegionExpression?
            do {
                region = try object.roi.map(RegionExpression.init)
            } catch {
                throw RecognitionAssetError.invalidConfiguration(configPath, reason: error.localizedDescription)
            }

            assets[name] = TemplateAsset(
                name: name,
                template: try loadGrayTemplate(at: url, displayPath: templatePath),
                region: region
            )
        }
        return assets
    }

    /// 按彩色读入后再转灰度，与采集画面的灰度转换方式一致；透明通道直接丢弃。
    private static func loadGrayTemplate(at url: URL, displayPath: String) throws -> Mat {
        let color = Imgcodecs.imread(filename: url.path, flags: ImreadModes.IMREAD_COLOR.rawValue)
        guard !color.empty() else {
            throw RecognitionAssetError.unreadableTemplate(displayPath)
        }

        let gray = Mat()
        Imgproc.cvtColor(src: color, dst: gray, code: .COLOR_BGR2GRAY)
        return gray
    }

    /// 只在指定目录查找，不退回资源根目录。
    private static func resourceURL(in bundle: Bundle, fileName: String, subdirectory: String) -> URL? {
        let name = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
    }
}
