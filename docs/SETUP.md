# הקמה — מאפס עד אפליקציה עובדת, בלי מחשב פיתוח

> כל השלבים כאן נעשים **מהדפדפן בלבד**. מחשב עם Flutter לא נדרש — גיטהאב בונה
> את האפליקציה בשבילנו (‏workflow בשם "Build app"), ואת ה-backend פורסים
> ב-workflow בשם "Deploy functions".

## מה כבר יש

- [x] פרויקט Firebase (נוצר בקונסולה)
- [x] הקוד בגיטהאב, כולל ה-workflows

## שלב 1 · שדרוג הפרויקט ל-Blaze

הפונקציה שלנו פונה החוצה (ל-Claude), וזה דורש את תוכנית **Blaze** (תשלום לפי
שימוש; בהיקף פיילוט — שקלים בודדים אם בכלל).

1. [console.firebase.google.com](https://console.firebase.google.com) ← הפרויקט שלך.
2. למטה משמאל: **Upgrade** ← בחירת Blaze ← מחברים כרטיס אשראי.
3. מומלץ: הגדרת התראת תקציב (Budget alert) על 50 ש"ח — שקט נפשי.

## שלב 2 · מפתח API של Anthropic

1. נרשמים ב-[console.anthropic.com](https://console.anthropic.com).
2. ‏**API Keys** ← ‏Create Key ← מעתיקים ושומרים במקום בטוח (מוצג פעם אחת).
3. מומלץ: ‏Settings ← Limits ← הגדרת תקרת הוצאה חודשית (Spend limit).

## שלב 3 · שני הסודות בענן (דרך Cloud Shell — בדפדפן)

הפונקציה קוראת שני סודות מ-Secret Manager: מפתח ה-API של Anthropic, ומפתח
משותף שהאפליקציה שולחת (APP_KEY — פשוט מחרוזת ארוכה אקראית שממציאים).

1. פותחים [console.cloud.google.com](https://console.cloud.google.com) ← בוחרים
   את אותו פרויקט ← לוחצים על אייקון ה-**Cloud Shell** (`>_` למעלה מימין).
2. בטרמינל שנפתח (זה מחשב זמני בענן, לא שלך):

   ```bash
   firebase functions:secrets:set ANTHROPIC_API_KEY
   # מדביקים את מפתח ה-API כשמתבקשים

   firebase functions:secrets:set APP_KEY
   # מדביקים מחרוזת אקראית ארוכה שהמצאתם, למשל פלט של:
   #   openssl rand -hex 24
   ```

## שלב 4 · חשבון שירות לפריסה מגיטהאב

כדי שגיטהאב יוכל לפרוס בשמך:

1. ‏[console.cloud.google.com/iam-admin/serviceaccounts](https://console.cloud.google.com/iam-admin/serviceaccounts)
   ← הפרויקט ← **Create service account** ← שם: `github-deployer`.
2. תפקיד (Role): **Editor** ← ‏Done. ‏(מספיק לפיילוט; אפשר לצמצם בהמשך.)
3. לוחצים על החשבון שנוצר ← לשונית **Keys** ← ‏Add key ← ‏Create new key ←
   ‏JSON ← נשמר קובץ למחשב/טלפון.

## שלב 5 · סודות ב-GitHub

ב-repo: ‏**Settings ← Secrets and variables ← Actions ← New repository secret**:

| שם | ערך |
|---|---|
| `FIREBASE_PROJECT_ID` | מזהה הפרויקט (מופיע ב-Firebase ← Project settings) |
| `FIREBASE_SERVICE_ACCOUNT` | כל תוכן קובץ ה-JSON משלב 4 (להדביק כמו שהוא) |

## שלב 6 · פריסת ה-backend

‏**Actions** ← ‏"Deploy functions" ← ‏**Run workflow**. בסיום (ירוק), כתובת
הפונקציה תהיה:

```
https://europe-west1-<FIREBASE_PROJECT_ID>.cloudfunctions.net/companionTurnHttp
```

(אפשר לראות אותה גם ב-Firebase ← Functions.)

## שלב 7 · חיבור האפליקציה ל-AI

מוסיפים עוד שני סודות ב-GitHub (כמו בשלב 5):

| שם | ערך |
|---|---|
| `COMPANION_ENDPOINT` | הכתובת משלב 6 |
| `COMPANION_APP_KEY` | אותו APP_KEY שהומצא בשלב 3 |

## שלב 8 · בנייה והתקנה

1. פעם אחת: ‏**Settings ← Pages ← Source: GitHub Actions** (מפעיל את גרסת הווב).
2. ‏**Actions** ← ‏"Build app" ← ‏**Run workflow** (או פשוט לדחוף קוד — זה רץ לבד).
3. בסיום:
   - **טאבלט אנדרואיד:** נכנסים לריצה ← ‏Artifacts ← מורידים את
     `creative-aac-apk` ← מעבירים לטאבלט ומתקינים (לאשר "התקנה ממקור לא מוכר").
   - **כל דפדפן (כולל אייפד):** ‏`https://<שם-המשתמש>.github.io/creative-aac/`

## הערות

- **בלי שלבים 1–7 האפליקציה עדיין עובדת** — במצב דמו אופליין. אפשר להתקין
  ולהתרשם עוד לפני חיבור ה-AI.
- **אבטחה בפיילוט:** ה-APP_KEY מוטמע באפליקציה/בווב וניתן לחילוץ ע"י מי
  שמתאמץ. לפיילוט סגור זה סביר — ההגנות האמיתיות הן תקרת ההוצאה (שלב 2)
  והתראת התקציב (שלב 1). לפני פתיחה לקהל רחב נעבור לאימות אמיתי.
- **פרטיות:** שום תוכן אישי לא נשמר בענן — הפרופיל, היצירות והלוג נשארים על
  המכשיר. הפונקציה מעבירה ולא שומרת.
