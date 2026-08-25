import { useState } from 'react'
import {
  ArrowDown,
  ArrowRight,
  Camera,
  Leaf,
  Map,
  Menu,
  ShieldCheck,
  Sprout,
  Store,
  X,
} from 'lucide-react'
import { CornScrollScene } from './components/CornScrollScene'
import { FarmerDemo } from './components/FarmerDemo'

function App() {
  const [menuOpen, setMenuOpen] = useState(false)

  const closeMenu = () => setMenuOpen(false)

  return (
    <div className="app-shell">
      <a className="skip-link" href="#main-content">Skip to content</a>
      <div className="field-texture" aria-hidden="true" />
      <CornScrollScene />

      <header className="site-header">
        <a className="brand" href="#top" onClick={closeMenu} aria-label="Farmable home">
          <span className="brand-mark"><Sprout size={22} aria-hidden="true" /></span>
          <span>Farmable</span>
        </a>

        <button
          aria-controls="site-navigation"
          aria-expanded={menuOpen}
          aria-label={menuOpen ? 'Close navigation' : 'Open navigation'}
          className="menu-button"
          onClick={() => setMenuOpen((open) => !open)}
          type="button"
        >
          {menuOpen ? <X aria-hidden="true" /> : <Menu aria-hidden="true" />}
        </button>

        <nav className={menuOpen ? 'site-nav site-nav--open' : 'site-nav'} id="site-navigation" aria-label="Main navigation">
          <a href="#field-plan" onClick={closeMenu}>Field plan</a>
          <a href="#crop-check" onClick={closeMenu}>Crop check</a>
          <a href="#market-route" onClick={closeMenu}>Markets</a>
          <a className="nav-cta" href="#demo" onClick={closeMenu}>Try the demo</a>
        </nav>
      </header>

      <main id="main-content">
        <section className="hero" id="top" aria-labelledby="hero-heading">
          <div className="hero-copy">
            <p className="eyebrow">Built for small farms, weak signal and real decisions</p>
            <h1 id="hero-heading">Know what to plant. Know when to sell.</h1>
            <p className="hero-intro">
              Farmable puts field checks, crop costs and nearby market prices in one phone-first view for South African smallholders.
            </p>
            <div className="hero-actions">
              <a className="primary-button" href="#demo">Try the farmer view <ArrowRight size={19} aria-hidden="true" /></a>
              <a className="secondary-button" href="#field-plan">See how it works <ArrowDown size={19} aria-hidden="true" /></a>
            </div>
            <div className="hero-notes" aria-label="Product principles">
              <span><ShieldCheck size={17} aria-hidden="true" /> Offline-first concept</span>
              <span><Camera size={17} aria-hidden="true" /> Camera-led tasks</span>
              <span><Leaf size={17} aria-hidden="true" /> Advice shows its limits</span>
            </div>
          </div>
          <p className="scroll-note"><span /> Scroll to open the cob</p>
        </section>

        <section className="story-section story-section--start" id="field-plan" aria-labelledby="field-heading">
          <article className="story-panel">
            <div className="story-meta"><span>01</span><Map size={22} aria-hidden="true" /></div>
            <p className="section-kicker">Field plan</p>
            <h2 id="field-heading">Start with the ground you have.</h2>
            <p>
              Photograph the soil, walk the plot and mark each crop zone. The plan stays on the phone, so a lost signal does not erase the field.
            </p>
            <div className="story-detail">
              <span>Phone camera</span>
              <span>Walk-the-boundary map</span>
              <span>Local farm record</span>
            </div>
          </article>
        </section>

        <section className="story-section story-section--end" id="crop-check" aria-labelledby="crop-heading">
          <article className="story-panel story-panel--gold">
            <div className="story-meta"><span>02</span><Camera size={22} aria-hidden="true" /></div>
            <p className="section-kicker">Crop check</p>
            <h2 id="crop-heading">Check five plants, not fifty menus.</h2>
            <p>
              A short camera flow asks for clear plant photos and returns one plain next step. If the image is unclear or the result is uncertain, Farmable says so.
            </p>
            <div className="story-detail">
              <span>Works on the device</span>
              <span>Confidence shown</span>
              <span>No automatic pesticide dose</span>
            </div>
          </article>
        </section>

        <section className="story-section story-section--start" id="market-route" aria-labelledby="market-heading">
          <article className="story-panel story-panel--dark">
            <div className="story-meta"><span>03</span><Store size={22} aria-hidden="true" /></div>
            <p className="section-kicker">Market route</p>
            <h2 id="market-heading">Walk into the market with a number.</h2>
            <p>
              Compare dated prices, travel distance and recorded costs before loading the harvest. Formal markets and nearby informal traders sit in the same decision.
            </p>
            <div className="story-detail">
              <span>Source and date visible</span>
              <span>Trip cost included</span>
              <span>Stale prices marked</span>
            </div>
          </article>
        </section>

        <FarmerDemo />

        <section className="closing-section" aria-labelledby="closing-heading">
          <div>
            <p className="section-kicker">Hackathon frontend</p>
            <h2 id="closing-heading">Take the idea into the field.</h2>
            <p>This branch demonstrates the product story and farmer-facing interaction. Live services can connect behind the same views later.</p>
          </div>
          <a className="primary-button" href="#top">Return to the field <ArrowRight size={19} aria-hidden="true" /></a>
        </section>
      </main>

      <footer className="site-footer">
        <a className="brand brand--footer" href="#top" aria-label="Farmable home">
          <span className="brand-mark"><Sprout size={22} aria-hidden="true" /></span>
          <span>Farmable</span>
        </a>
        <p>Demo frontend for the Geekulcha Annual Hackathon 2026.</p>
      </footer>
    </div>
  )
}

export default App
