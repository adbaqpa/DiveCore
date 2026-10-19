# Gizlilik Politikası — DiveLog

**Son güncelleme:** 14 Ekim 2026
**Sürüm:** 1.0
**Uygulama:** DiveLog — Dalış Bilgisayarı (Apple Watch / iPhone)

---

## 1. Özet

DiveLog, dalış verilerinizi **cihazınızda** tutan bir uygulamadır. Verilerinizi
toplayan bir sunucumuz, reklam ağı ya da analitik sağlayıcımız **yoktur**.
Dalış kayıtlarınız yalnızca cihazınızda ve — siz açarsanız — Apple'ın
**iCloud gizli alanınızda** saklanır.

> **Kısa cevap:** Veriniz bizde değil, sizde.

---

## 2. Hangi Verileri Topluyoruz?

Uygulama aşağıdaki verileri **üretir** (cihaz sensörlerinden okur) ve
**yerel olarak saklar**:

| Veri | Kaynak | Neden | Saklama yeri |
|---|---|---|---|
| Derinlik ve dalış süresi | CoreMotion (`CMAltimeter`) | Dalış bilgisayarı çalışması için **zorunlu** | Cihaz + iCloud (isteğe bağlı) |
| Su sıcaklığı | CoreMotion termal sensörü | Profil grafiği | Cihaz + iCloud (isteğe bağlı) |
| Su basıncı / yükseklik | CoreMotion | Başlangıç yüzey referansı | Cihaz |
| Yükseliş/iniş hızı | Türetilir | Hız alarmı | Cihaz + iCloud (isteğe bağlı) |
| Dokular (N₂ basınçları) | Türetilir (Bühlmann) | Dekompresyon hesabı | Cihaz (hesaplanır, saklanmaz) |
| Deko durakları, GF99, NDL | Türetilir | Dalış raporu | Cihaz + iCloud (isteğe bağlı) |
| Oksijen yükü (PO₂/CNS/OTU) | Türetilir | Güvenlik uyarıları | Cihaz + iCloud (isteğe bağlı) |
| **GPS konumu** | CoreLocation | Dalış noktası ve rota haritası | Cihaz + iCloud (isteğe bağlı) |
| Hareket (manyetik / pusola) | CoreMotion | Pusola göstergesi | Cihaz (saklanmaz) |
| Cihaz adı / seri | Cihaz bilgisi | Senkronizasyonda çakışma çözümü | Cihaz |
| Satın alma durumu | Apple StoreKit | Pro özelliklerinin açılması | Apple sunucuları (Apple'ın kendi sistemi) |

**Not:** Uygulama **ad, e-posta, telefon, kullanıcı adı veya iletişim
bilgisi toplamaz.** Hesap sistemi yoktur; oturum açma yapılmaz.

---

## 3. Veriler Nerede Saklanır?

### 3.1 Cihazınızda

Tüm dalış kayıtları ve ayarlar uygulamanın kendi **kapsayıcısında**
(`Application Support`) saklanır. Uygulama silinirse veriler de silinir.

### 3.2 iCloud gizli alanınızda (isteğe bağlı)

Watch ⇄ iPhone senkronizasyonu ve Apple Health yazma işlemleri Apple'ın
**özel veri kapsayıcılarını** (`NSFileCoordinator` / CloudKit özel alan)
kullanır. Bu veriler:

- sizin Apple ID hesabınıza aittir,
- Apple'ın şifreleme ve "gizli alan" hizmetiyle korunur,
- **DiveLog geliştiricileri tarafından erişilemez**.

Senkronizasyonu Ayarlar'dan kapatabilirsiniz; kapatıldığında veriler yalnızca
cihazda kalır.

### 3.3 Apple'ın kendi sistemleri

- **Apple Health:** Sağlık verisi yazma izni verirseniz dalış kayıtları
  HealthKit'e yazılır. Bu veri Apple'ın sağlık veri saklama kurallarına
  tabidir ve DiveLog tarafından okunamaz.
- **StoreKit:** Satın alım durumu Apple'ın ödeme sisteminde tutulur.
  Uygulama kart veya banka bilginize **hiçbir zaman** erişmez.

---

## 4. Verileri Kimlerle Paylaşıyoruz?

**Kimseyle.** Uygulama:

- üçüncü taraf reklam SDK'sı **içermez**,
- analitik veya telemetri servisi **göndermez**,
- çökme raporlarını otomatik olarak yüklemez,
- kullanıcı verisini kendi sunucularımıza **göndermez**.

Tek istisna: **verileri siz paylaşmayı seçerseniz** (UDDF/FIT/JSON dışa aktarma
veya sistem paylaşım panosu). Bu durumda dosya, o an seçtiğiniz uygulamaya
gider ve o uygulamanın gizlilik politikası geçerlidir. **DiveLog,
paylaşılan verinin içeriğini göremez.**

---

## 5. Veri Güvenliği

| Önlem | Açıklama |
|---|---|
| Şifreleme (aktarım) | Uygulama ağ üzerinden kendi başına veri göndermez. |
| Şifreleme (depolama) | iCloud verileri Apple'ın cihaz üstü ve sunucu şifrelemesiyle korunur. |
| Erişim | Geliştirici erişimi yoktur; Apple'ın gizli alan modeli kullanılır. |
| Veri kaybı | Kayıtlar otomatik olarak yedeklenir; iCloud kapalıysa yedek yoktur. |
| Silme | "Tüm verileri sil" işlemi uygulama içinden veya silme yoluyla yapılır. |

---

## 6. Çocuklar

Uygulama 13 yaş üstü içindir ve çocuklara yönelik değildir. 13 yaşın
altındaki kullanıcılar uygulamayı kullanmamalıdır.

---

## 7. Üçüncü Taraf SDK'lar

Uygulama şu SDK'ları kullanır:

| SDK | Sağlayıcı | Kullanım | Veri gönderimi |
|---|---|---|---|
| StoreKit 2 | Apple | Satın alma | Apple'ın kendi ödeme akışı |
| HealthKit | Apple | Sağlık verisi yazma | Apple'ın kendi sağlık kapsayıcısı |
| CoreMotion | Apple | Derinlik, sıcaklık, pusola | Yok |
| CoreLocation | Apple | Konum | Konum yalnızca cihazda saklanır |
| WatchConnectivity | Apple | Watch ⇄ iPhone aktarımı | Apple'ın özel kanalı |

Üçüncü taraf reklam, analitik veya sosyal medya SDK'sı **yoktur**.

---

## 8. Haklarınız

Uygulama GDPR/KVKK kapsamında size şu hakları tanır:

- **Erişim:** Tüm dalış kayıtlarını uygulama içinden görüntüleyin veya
  dışa aktarın (JSON, UDDF, FIT).
- **Düzeltme:** Dalış notlarını ve etiketleri düzenleyin.
- **Silme:** Tek tek veya tümünü silin.
- **Taşınabilirlik:** Dışa aktarma ile verilerinizi başka uygulamaya taşıyın.
- **İtiraz / geri çekme:** Veri işlemeyi tamamen sonlandırmak için uygulamayı
  silmeniz yeterlidir.

Verileriniz yalnızca cihazınızda olduğu için, "verilerimi sil" talebi
uygulamanın kendisinden karşılanır; bir talep süreci başlatmaya gerek yoktur.

---

## 9. Değişiklikler

Bu politika değişirse:

- uygulama içindeki **Ayarlar → Gizlilik Politikası** sayfası güncellenir,
- mağaza açıklamasındaki sürüm notlarında belirtilir.

**Veri işleme biçimi köklü değişirse** (ör. sunucu eklenirse) kullanıcılardan
açıkça onay istenir.

---

## 10. İletişim

Sorularınız için: **privacy@divelog.app**

---

## 11. Apple Watch Ultra uyarısı

DiveLog bir dalış bilgisayarıdır ve üretici cihazlarının yerine geçmez.
Dekompresyon algoritmaları hayat kurtarıcı niteliktedir; gerçek dalışlardan
önce referans bilgisayarlarla ve yetkinli bir eğitmenle çapraz doğrulayın.
