import Index from "./pages/Index";

/**
 * SinRutina is one screen stack, not a site: there is nothing to route to, and a
 * URL bar full of paths would only add decisions. So the app mounts directly.
 */
const App = () => <Index />;

export default App;
