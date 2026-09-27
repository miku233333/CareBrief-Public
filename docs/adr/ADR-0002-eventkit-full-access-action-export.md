# ADR-0002：以 just-in-time EventKit full access 支援明確輸出、去重及同一 Session Undo

- 狀態：Accepted
- 日期：2026-07-11

## 背景

CareBrief 的 Action Cards 來自醫療及政府文件，必須先讓使用者查看 evidence、修正內容及逐項確認，才能寫入 Apple Calendar 或 Reminders。GH-8 同時要求 marker-backed duplicate detection 及只刪除本次建立項目的 Undo。

iOS 17 Calendar write-only access 足以建立 event，但不能讀取或刪除 Calendar items；Reminders 亦沒有對應 write-only 模式。因此 write-only 無法同時滿足 exact marker lookup、already-added result 及 Undo。另一方面，full access 比單純建立項目所需權限更廣，必須收窄請求時機、用途及 UI disclosure。

## 決策

1. Calendar 及 Reminders 權限分開、just-in-time；只在 final preview 按 Add，並且實際選擇了相應 destination 時請求。
2. iOS 17+ 使用 `requestFullAccessToEvents()` 及 `requestFullAccessToReminders()`；iOS 16 使用 `requestAccess(to:)` legacy fallback。iOS 17 Calendar `.writeOnly` 對本功能視為不足，會在 final Add 清楚要求升級 full access。
3. 同時提供新舊 usage descriptions：
   - `NSCalendarsFullAccessUsageDescription`
   - `NSCalendarsUsageDescription`
   - `NSRemindersFullAccessUsageDescription`
   - `NSRemindersUsageDescription`
4. Preview 在權限提示前解釋：建立的 edited action 可能透過使用者的 Apple account provider 同步；full access 只用於尋找 CareBrief marker、防止重複及支援同一 App process 的 Undo。
5. Core `ActionCard` 保持不可變。AppSupport 建立 editable `ActionDraft` 及 pure export preview；EventKit adapter 只接受已驗證的 export request，不接觸 OCR 圖片或 evidence quote。
6. 以 CryptoKit SHA-256 對 canonical payload 建立 marker。Payload 包括 source-document text hash、evidence rule/range、normalized edited payload 及 destination；EventKit 只保存 `carebrief://export/v1/<destination>/<digest>`，不保存 canonical payload、evidence quote、document UUID 或 responsible party。
7. EventKit full access 的讀取用途受 adapter contract 限制：
   - Calendar 只在 request 的日期範圍取得 events，並在 EventKit-owning actor 內 filter exact CareBrief marker；
   - Reminders 只使用 EventKit predicate，在 callback 內轉成 exact-marker、identifier-only snapshots；
   - 非匹配項目不跨 actor；所有項目都不返回 ViewModel、UI、analytics、log 或網路。
8. Duplicate detection 是 marker-backed best-effort，不宣稱資料庫 unique constraint。同 process 同 marker export 由 coordinator 序列化；跨裝置競態、provider 移除 marker或 event 被移出搜尋範圍仍可能造成重複。
9. Undo receipt 只來自本 process 的 successful create。刪除前核實 destination、item identifier、item type 及 exact marker；identifier 不存在、無法 resolve或 marker/type 不符時安全拒絕，不以 marker-only fallback、title、date 或 location 猜測另一項目。同一 identifier/type 仍保留 exact marker 時，即使使用者在 Apple App 修改其他可見欄位，Undo 仍會刪除本次由 CareBrief 建立的該項目。
10. Responsible party 預設只留在 CareBrief。Preview toggle 預設關閉；使用者明確開啟後，edited responsible label 才加入可見 notes，但不加入 marker。因 marker 刻意排除 responsible party，命中 duplicate 時既有 Apple item 不會更新 notes，UI 必須明示 `Already added` 沒有修改既有項目。
11. Preview 每次只顯示使用者選定的 App 語言，預設跟隨 iPhone，並容許持久覆蓋為繁中或英文；Apple 系統權限視窗仍跟隨 iPhone。易讀模式只縮短說明及收起技術細節，不可隱藏同步／權限警告，也不可改變 final Add 才要求權限的流程。

## 理由

- Full access 是同時完成 Calendar／Reminders 去重與可驗證 Undo 的必要條件，而不是預設瀏覽使用者行程的授權。
- Final-Add 才請求可把系統 permission prompt 與使用者剛選擇的動作連結，避免啟動、OCR、extract、edit 或 confirm 時過早索取。
- Pure AppSupport preview 及 testable gateway 把醫療文件 state 與 Apple framework object 分離，能用 fake 覆蓋 permission、duplicate、partial failure 及 Undo。
- Deterministic digest 讓相同 source text、evidence、edited payload 及 destination 重建相同 marker，同時不在 EventKit 暴露來源原文。
- Receipt、identifier、type 及 exact marker 的共同核實可避免 identifier drift 或 provider sync 時猜測性刪除其他項目，同時保留刪除本次實際建立項目的能力。

## 替代方案

### iOS 17 Calendar write-only access

拒絕作本 milestone 的主要模式。它更窄，但不能讀取 exact marker或刪除 created item，亦不能涵蓋 Reminders full-access requirement。若日後取消 duplicate detection／Undo，應重新評估。

### 系統 EventKit editor

拒絕作主要流程。它可讓使用者再次確認單一 Calendar event，但不能提供一致的 Calendar／Reminder batch preview、per-item duplicate result、partial failure receipt及同一閉環 Undo。

### Preview-only，不寫入 EventKit

拒絕。它未能完成 MAIC 展示所需的「一鍵加入日曆／提醒」行動閉環。

### 使用 title/date 比對重複

拒絕。標題及日期可能相同或被使用者修改，容易誤判及誤刪；只接受版本化 exact marker。

### 把 source quote、document ID 或 responsible party 放入 marker

拒絕。Marker 應只包含版本、destination及不可逆 digest；使用者可見 notes 亦不得自動加入 evidence quote或照顧者姓名。

## 影響

- 使用者會看到比 write-only 更廣的 Calendar full-access prompt，以及獨立 Reminders prompt；CareBrief 必須在 prompt 前清楚解釋用途。
- `SystemEventKitStoreGateway` 由專用 actor 持有單一 `EKEventStore`；MainActor coordinator 只接收 Sendable marker／identifier snapshots，避免同步 event query 阻塞 UI 或 EventKit framework object 跨 actor/store。
- Permission denied、restricted、write-only不足、沒有 default calendar/list、duplicate ambiguous、save/remove failure及 item missing 都要成為 safe domain result，draft 仍保留。
- Calendar item identifier 可因同步而改變；Undo 只保證 best-effort 且只限目前 process。
- identifier 無法 resolve 時不能分辨外部刪除與 provider identifier drift，因此回報安全的 item-not-found failure並保留 receipt，而不是宣稱已刪除或按 marker 猜刪。
- Responsible party／notes toggle 不參與 marker；再次 Add 命中 duplicate 時不會更新既有 notes，使用者需在 Apple app 查看或修改既有項目。
- 緊湊 UI 仍需在 Add 前持續顯示同步及 full-access 邊界；技術細節可用 DisclosureGroup 收起，但安全提示不可只靠首次引導。
- 沒有文件／draft persistence；EventKit items 由 Apple apps/provider 持久保存。

## 相容性

最低 iOS 16。Availability branch 隔離 iOS 17 full-access API，legacy iOS 16 authorization 映射為 domain full access。Xcode 26.6及27 beta 3 package tests、Xcode 27 warnings-as-errors iOS build及 built Info.plist readback是合併閘門。

## 私隱及安全

- 不硬編碼 credential、不加入網路、analytics或帳戶。
- 只使用合成資料進行 Simulator EventKit runtime驗證。
- Full access 不會成為 generic Calendar browser；gateway query 必須帶 exact marker，只把匹配項目的 identifier／marker snapshot交給 coordinator，不提供列出或展示其他 items 的公開介面。
- EventKit notes 只包含 final preview 顯示的 edited payload；responsible party另行 opt-in。未編輯且等於 evidence quote 的 detail 不會加入 notes或 marker payload；使用者明確改寫後的 detail 才可按 preview 內容同步。

## 回滾

正常 revert GH-8 EventKit adapter、models、UI、usage descriptions及本 ADR。Rollback 不會自動刪除使用者已建立的 Calendar／Reminder items；仍在同一 App process且 receipt有效時可用 Undo，否則由使用者在 Apple apps 刪除。不得 force push或改寫協作歷史。
