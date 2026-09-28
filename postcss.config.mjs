// Tailwind 4 ships its PostCSS plugin as @tailwindcss/postcss and prefixes vendors itself (Lightning CSS),
// so autoprefixer is no longer in the chain.
export default { plugins: { '@tailwindcss/postcss': {} } };
