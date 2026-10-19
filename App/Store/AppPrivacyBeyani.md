# ADIM 3 — App Store Connect "App Privacy" Beyanı

> Bu belge, `AppStoreListing` ve `AppPrivacy` (DiveCore) tanımlarının
> uygulama üzerinden birebir karşılığıdır. Beyan değişirse
> `Sources/DiveCore/Services/Commerce/AppPrivacy.swift` güncellenmelidir.

---

## 1. Adım adım doldurma

App Store Connect → *Uygulamanız* → **Dağıtım** → **App Privacy** bölümü.

### 1.1 Veri toplanıyor mu?

| Soru | Cevap |
|---|---|
| Uygulamanız kullanıcı verilerini **topluyor** mu? | **EVET** |
| Veriler yalnızca cihazda kalıyor mu? | Hayır — iCloud gizli alanı ve HealthKit kullanılıyor |
| Veriler sunucunuza gidiyor mu? | **HAYIR** (kritik soru) |

> **Yol haritası:** "Veri toplanıyor mu?" → **EVET** → "Verileriniz
> uygulamanın dışına çıkıyor mu?" → Konum, sağlık ve kullanıcı içeriği için
> **EVET** (iCloud), tanımlayıcı ve satın almalar için **HAYIR**.

### 1.2 Beyan edilecek veri tipleri

| # | Veri tipi | Toplama | Amaç | Kullanıcıya bağlı | İzleme | Silme |
|---|---|---|---|---|---|---|
| 1 | **Konum** (Kaba + Hassas) | Özel iCloud | Uygulama işlevi | Evet | Hayır | Evet |
| 2 | **Sağlık ve Fitness** | Özel iCloud | Uygulama işlevi | Evet | Hayır | Evet |
| 3 | **Kullanıcı İçeriği** (günlük/notlar) | Özel iCloud | Uygulama işlevi | Evet | Hayır | Evet |
| 4 | **Tanımlayıcılar** (cihaz kimliği) | Toplanmıyor | Uygulama işlevi | Hayır | Hayır | Evet |
| 5 | **Satın Alımlar** | Toplanmıyor | Uygulama işlevi | Hayır | Hayır | Evet |

### 1.3 Her veri tipi için ayrıntılar

#### 1) Konum

| Soru | Cevap |
|---|---|
| Kullanılan konum türleri | **Kaba konum** ve **Hassas konum** |
| Neden? | Dalış noktasını kaydetmek, GPS rota haritası (Pro) |
| Toplama yöntemi | Uygulama çalışırken (dalış sırasında, yalnızca yüzeyde) |
| Veri uygulama dışına çıkıyor mu? | **EVET** — iCloud gizli alanı (kullanıcının kendi hesabı) |
| Şifreli mi? | **EVET** (cihazda ve iCloud'da) |
| Silme talebi alabilir miyim? | **EVET** (Ayarlar → Tüm Verileri Sil) |

> **Kullanıcıya gösterilecek metin:**
> "Konumunuz, dalış noktanızı günlüğe kaydetmek ve iPhone uygulamasında
> rota haritasını göstermek için kullanılır. Konum yalnızca dalış sırasında
> ve yüzeyde okunur; su altında okunmaz."

#### 2) Sağlık ve Fitness

| Soru | Cevap |
|---|---|
| Sağlık verisi türleri | **Dalış verileri** (derinlik, süre, dekompresyon) |
| Neden? | Dalış bilgisayarı çalışması ve Apple Health'e yazma |
| Toplama yöntemi | Uygulama çalışırken |
| Veri uygulama dışına çıkıyor mu? | **EVET** — iCloud ve (izin verilirse) Apple Health |
| Şifreli mi? | **EVET** |
| Silme talebi | **EVET** |

> **Kullanıcıya gösterilecek metin:**
> "Dalış kayıtlarınız Apple Health'e yazmak istediğinizde, yalnızca o izin
> verildiğinde ve Apple'ın sağlık veri kurallarına göre saklanır. DiveLog
> HealthKit verisini okuyamaz."

#### 3) Kullanıcı İçeriği

| Soru | Cevap |
|---|---|
| İçerik türleri | **Dalış günlüğü ve kullanıcı notları** |
| Neden? | Uygulamanın temel işlevi |
| Toplama yöntemi | Uygulama çalışırken (kullanıcı oluşturur) |
| Uygulama dışına çıkıyor mu? | **EVET** — iCloud gizli alanı |
| Şifreli mi? | **EVET** |
| Silme talebi | **EVET** |

#### 4) Tanımlayıcılar

| Soru | Cevap |
|---|---|
| Cihaz kimliği | Kullanılır, ancak **cihaz dışına çıkmaz** |
| Neden? | Watch ⇄ iPhone senkronizasyonunda çakışma çözümü için kararlı anahtar |
| Toplanmıyor mu? | **Doğru** (yalnızca yerel karşılaştırma) |

#### 5) Satın Alımlar

| Soru | Cevap |
|---|---|
| Satın alma geçmişi | StoreKit üzerinden Apple'da tutulur |
| Uygulamanın kendi sunucusu | **HAYIR** |
| Toplanmıyor mu? | **Doğru** (yalnızca Apple'ın ödeme sistemi) |

---

## 2. Kesinlikle **HAYIR** denmesi gerekenler

Bu sorulara "EVET" demek uygulamayı yanlış tanımlar:

| Soru | Cevap | Neden |
|---|---|---|
| Veriler reklam amacıyla kullanılıyor mu? | **HAYIR** | Reklam SDK'sı yok |
| Veriler analiz/ölçüm amacıyla kullanılıyor mu? | **HAYIR** | Analitik servisi yok |
| Veriler 3. taraf SDK'larla paylaşılıyor mu? | **HAYIR** | Yalnızca Apple SDK'ları |
| Kullanıcı "izleme" yapılıyor mu? | **HAYIR** | ATT uyarısı gösterilmez |
| Konum arka planda kullanılıyor mu? | **HAYIR** | Yalnızca aktif dalışta |
| Kullanıcı adı/e-posta toplanıyor mu? | **HAYIR** | Hesap sistemi yok |
| Kullanıcının belirlediği "kişiselleştirme" yapılıyor mu? | **HAYIR** | Reklam/analiz yok |

> **Sonuç:** `NSUserTrackingUsageDescription` **gerekmez** ve
> `Info.plist`'e eklenmemelidir. Yanlışlıkla eklenmek, uygulamanın ATT
> izni istemesine yol açar ve kullanıcıyı gereksiz bir uyarıyla karşılaştırır.

---

## 3. Kullanıcıya gösterilen özet

Beyan tamamlandığında App Store, uygulama sayfasında otomatik olarak şu
benzeri bir etiket gösterir:

> **"DiveLog Konum, Sağlık ve Fitness, Kullanıcı İçeriği ve Diğer Veriler
> Kullanır"** ve **"Veriler Kullanıcıyla Bağlantılı"**

Bu etiket, satışa doğrudan etki eder. Uygulamanın gerçek davranışı
(cihazda saklama) nedeniyle etiket küçük kalır; bu **doğru** davranıştır ve
gizlenmemelidir.

---

## 4. Avrupa / GDPR ek beyanı

Ek bölümler (yalnızca dağıtıldığınız bölgeye göre):

### 4.1 Veri sorumluları

| Soru | Cevap |
|---|---|
| Veri sorumlusu kim? | Uygulama geliştiricisi (aşağıdaki e-posta) |
| Veri işleyen kim? | Apple (iCloud, HealthKit) — alt işleyici |
| AB temsilcisi gerekli mi? | AB dışındaysanız ve düzenlemeye tabiyseniz gerekebilir |

### 4.2 Aktarım

| Soru | Cevap |
|---|---|
| Veri AB dışına aktarılıyor mu? | Yalnızca kullanıcının kendi iCloud hesabı aracılığıyla (Apple'ın kendi veri yerleşimi) |
| Standart sözleşmeler (SCC) var mı? | Uygulama geliştiricisi olarak kendi sunucunuz yok; doğrudan aktarım yapılmaz |

### 4.3 Veri koruma hakları

| Hak | Nasıl karşılanıyor |
|---|---|
| Erişim | Uygulama içinden dışa aktarma (JSON/UDDF/FIT) |
| Düzeltme | Not ve etiket düzenleme |
| Silme | Ayarlar → Tüm Verileri Sil |
| Taşınabilirlik | Dışa aktarma |
| İşleme kısıtlama | Uygulamayı silmek yeterlidir |
| İtiraz | privacy@divelog.app |

### 4.4 Çocukların verileri

| Soru | Cevap |
|---|---|
| 13 yaş altı çocuk verisi toplanıyor mu? | **HAYIR** (yaş bandı 13+) |

---

## 5. Yaygın reddi nedenleri ve önlemleri

| Reddi nedeni | Önlem |
|---|---|
| Gizlilik politikası URL'si 404 | Politika yayınlanmadan başvuru yapmayın |
| Beyan ile gerçek davranış çelişiyor | `AppPrivacy.declarations` testleriyle eşleştirin |
| ATT izni isteniyor ama reklam yok | `NSUserTrackingUsageDescription` eklemeyin |
| "Güvenlik özelliği ücretli" şüphesi | Paywall'da ve mağaza metninde güvenlik garantisi açıkça yazılı |
| HealthKit açıklaması eksik | `App/iOS/Info.plist` içinde tanımlı, ADIM 13 doğrulamasıyla denetlenir |
| Sürüm notları boş | Her sürümde gerçek değişiklik listelenir |

---

## 6. Sürüm notu — "DiveLog ne topluyor?"

Bu bölümü mağaza açıklamasına ve uygulama içindeki Gizlilik sayfasına
kopyalayabilirsiniz:

> **DiveLog ne topluyor?**
>
> Dalış derinliği, süresi, sıcaklığı, gaz bilgisi ve — isterseniz —
> dalış noktanızın konumu. Tüm bu veriler cihazınızda ve sizin iCloud
> gizli alanınızda saklanır.
>
> **Toplamadığımız:** Ad, e-posta, telefon numarası, reklam kimliği,
> konum geçmişi tarama verisi, davranış analitiği.
>
> **Sunucumuz yok.** Uygulamayı kullandığınızda veriniz bize ulaşmaz.
