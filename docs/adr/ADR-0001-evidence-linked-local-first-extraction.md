# ADR-0001：以本機、deterministic、證據連結抽取建立 CareBriefCore

- 狀態：Accepted
- 日期：2026-07-11

## 背景

CareBrief 的產品承諾是把醫院及政府文件變成可執行 Action Cards，同時讓每一項結果返回原文。第一個產品切片需要可在沒有 iOS UI、Vision、相機、雲端服務或 API key 的環境重現及測試。

## 決策

1. 建立純 Foundation `CareBriefCore` Swift Package，iOS App 只作呼叫端。
2. 所有 Action Card 必須包含 `SourceEvidence`：文件 ID、原文、rule ID 及 UTF-16 range。
3. 第一階段使用 deterministic 規則式抽取，只解析明確支援的繁體中文及英文日期／時間與行動關鍵字。
4. 不確定或未支援內容不得補作；需要人工判斷的結果標記 `needsReview`，完全未命中時回傳 warning。
5. 不加入網路、第三方 dependency、持久化、診斷、醫療建議或法律建議。

## 理由

- UTF-16 range 可直接對應 Apple OCR、`NSRange` 與日後 SwiftUI 原文高亮。
- deterministic 規則可重現、可回歸測試，適合作為後續 OCR／可選 AI pipeline 的安全基線。
- 純 Foundation core 可同時由 command-line demo、Linux CI 及未來 iOS App 重用。
- 本機處理與零 credential 降低早期原型的私隱及秘密管理風險。

## 替代方案

### 直接在 SwiftUI View 內解析

拒絕。會把 UI、OCR 與 domain logic 綁在一起，難以測試及跨平台重用。

### 第一版直接呼叫雲端 LLM

拒絕。會引入網路、費用、憑據、私隱及非 deterministic 行為，而且不能取代來源證據與人工確認。

### 只輸出一般摘要

拒絕。摘要不能滿足「Document → Evidence-linked Action Cards」的核心定位。

## 影響

- 後續 iOS App 應直接依賴 `CareBriefCore` 公開模型及 `DocumentActionExtracting` protocol。
- Vision／OCR 或 AI extractor 可在日後實作同一 protocol，但仍必須提供可解析的 UTF-16 evidence。
- 規則式抽取覆蓋有限；UI 必須顯示 confidence、review 狀態及原文，而不是把結果當醫療或法律事實。

## 相容性

Package 使用 Swift 5 language mode、Foundation、iOS 16+ 及 macOS 13+。公開模型可 Codable，方便 demo、測試及日後 app state。

## 回滾

未合併前關閉或不合併 GH-2 PR。合併後使用正常 revert commit 移除 Package 與 ADR，不 force push 或改寫協作歷史。
