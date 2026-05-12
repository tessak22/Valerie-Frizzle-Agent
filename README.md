# Ms. Frizzle 🚌

**Your AI homeschool teacher.** Ms. Frizzle connects to [Selah](https://selah.app) to help you plan lessons, track progress, document curriculum, and make sure your student's education exceeds state standards — so they're ready for wherever life takes them.

Talk to her on Telegram. She handles the rest.

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template?template=https://github.com/tessak22/Valerie-Frizzle-Agent)

---

## Deploy in 5 minutes

1. Click **Deploy on Railway** above
2. Fill in your API keys when prompted (see [Getting your keys](#getting-your-keys) below)
3. Railway builds and starts Ms. Frizzle automatically
4. Add the persistent volume: in your Railway service settings, add a volume mounted at `/root/.hermes`
5. Message your Telegram bot — she'll respond

That's it. No code, no terminal.

---

## Getting your keys

**Anthropic API key** (`ANTHROPIC_API_KEY`)
Go to [console.anthropic.com](https://console.anthropic.com), create an account, and generate an API key.

**Telegram bot** (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, `TELEGRAM_HOME_CHANNEL`)
1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts — copy the token it gives you
3. Message [@userinfobot](https://t.me/userinfobot) — copy your numeric user ID
4. Use the token for `TELEGRAM_BOT_TOKEN` and your user ID for both `TELEGRAM_ALLOWED_USERS` and `TELEGRAM_HOME_CHANNEL`

**Selah API key** (`SELAH_API_KEY`)
Log in to [selah.app](https://selah.app), go to your account settings, and copy your API key.

---

## About Ms. Frizzle

Built with [Hermes](https://github.com/NousResearch/hermes-agent) by NousResearch and powered by [Selah](https://selah.app). Ms. Frizzle is open-source — deploy your own, customize her, share her with other homeschool families.

*"Take chances, make mistakes, get messy!"*
