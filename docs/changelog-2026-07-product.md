
        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-teal-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">🔑</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Operator visibility & control</h3>
              <p class="text-white/40 leading-relaxed">Run one hart instance for all your agents and see everything they make. A new admin token unlocks cross-owner discovery — <code>hart admin owners</code> and <code>hart admin list</code> — plus <code>hart admin mv</code> to move or rename any artifact in place, keeping its full version history, visibility, and password. Passwords stay hashed, so the admin view shows presence, never secrets.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-emerald-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">📊</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Live instance dashboard</h3>
              <p class="text-white/40 leading-relaxed">A built-in operational status page at <code>/_status</code> gives every instance an at-a-glance health and activity view — no extra service to stand up.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-blue-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">🔒</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Visibility & sharing</h3>
              <p class="text-white/40 leading-relaxed">Every artifact is unlisted, public, or private. Private pages are password-gated — browsers get an unlock page, agents send a read-key header. Public ones surface in the discovery feed at <code>/explore</code> and <code>/o/&lt;owner&gt;</code>.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-purple-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">🏷️</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Namespaces you own</h3>
              <p class="text-white/40 leading-relaxed">On an open instance, the first write to a new owner claims it. Pass an owner-key and that namespace is yours — further writes need the key, so your agents' work stays under names only you control.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-amber-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">⚛️</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Publish anything self-contained</h3>
              <p class="text-white/40 leading-relaxed">Pipe a self-contained HTML file — or JSX, transpiled in-browser with a same-origin React runtime, no build step, no CDN. Every page is served under a strict CSP sandbox, and a publish-time linter blocks anything that reaches off-page.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-rose-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">🕒</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Immutable versions + live data</h3>
              <p class="text-white/40 leading-relaxed">Re-publishing appends a version; latest tracks the newest, old versions stay pinned, and rollback reverts instantly. Publish a template once, then push just the data with <code>hart data</code> and the same URL re-renders.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-cyan-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">🔄</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Deliverables that keep themselves fresh</h3>
              <p class="text-white/40 leading-relaxed">A dashboard no longer needs a babysitter. Point an artifact at a URL or command and hart re-fetches its data on a schedule (<code>hart refresh</code>); turn on live mode (<code>hart live</code>) and the page repaints in the browser with no reload. A freshness SLA (<code>hart fresh</code>) flags anything that goes quiet.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-amber-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">💬</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Feedback, straight from the CLI</h3>
              <p class="text-white/40 leading-relaxed">Agents and operators hit friction that used to vanish silently. <code>hart feedback</code> sends a bug, idea, or note in one call — best-effort, never in the way — so the people who run hart actually hear about it.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-yellow-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">⭐</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">hart Pro — open-core, honest keys</h3>
              <p class="text-white/40 leading-relaxed">The CLI stays fully free. A license key unlocks higher storage limits and an audit log of who changed what. Keys are Ed25519-signed and verified offline — no phone-home. Buying is agent-first: <code>hart upgrade</code> hands you a checkout link, and <code>hart license</code> activates it.</p>
            </div>
          </div>
        </div>

        <div class="feature-card rounded-xl p-6">
          <div class="flex items-start gap-4">
            <div class="w-12 h-12 rounded-lg bg-indigo-500/10 flex items-center justify-center flex-shrink-0">
              <span class="text-2xl">👥</span>
            </div>
            <div>
              <h3 class="text-xl font-semibold text-white mb-2">Teams &amp; sign-in with your IdP</h3>
              <p class="text-white/40 leading-relaxed">Share a namespace with per-member keys — each teammate acts under their own identity, visible in the audit log, revocable in one command. New members self-onboard with <code>hart join</code>, signing in through any OpenID Connect provider you configure. You bring the identity provider; hart brings the wiring.</p>
            </div>
          </div>
        </div>
