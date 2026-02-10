// ============================================
// Harding Website JavaScript
// ============================================

// Global Harding interpreter instance
let hardingReady = false;

// Load Harding interpreter
document.addEventListener('DOMContentLoaded', () => {
    // Mobile navigation toggle
    const navToggle = document.querySelector('.nav-toggle');
    const navMenu = document.querySelector('.nav-menu');

    if (navToggle && navMenu) {
        navToggle.addEventListener('click', () => {
            navMenu.classList.toggle('active');
        });

        // Close menu when clicking a link
        navMenu.querySelectorAll('a').forEach(link => {
            link.addEventListener('click', () => {
                navMenu.classList.remove('active');
            });
        });
    }

    // ============================================
    // Example Tabs
    // ============================================
    const tabBtns = document.querySelectorAll('.tab-btn');
    const tabPanels = document.querySelectorAll('.tab-panel');

    tabBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            const tabId = btn.dataset.tab;

            // Deactivate all tabs
            tabBtns.forEach(b => b.classList.remove('active'));
            tabPanels.forEach(p => p.classList.remove('active'));

            // Activate selected tab
            btn.classList.add('active');
            const panel = document.getElementById(`tab-${tabId}`);
            if (panel) {
                panel.classList.add('active');
            }
        });
    });

    // ============================================
    // Playground
    // ============================================
    const playgroundCode = document.getElementById('playground-code');
    const runBtn = document.getElementById('run-btn');
    const clearBtn = document.getElementById('clear-btn');
    const output = document.getElementById('output');

    // Example code snippets
    const examples = {
        hello: `"Hello, World!" println`,

        factorial: `"Factorial function"
factorial := [:n |
    (n <= 1) ifTrue: [^ 1].
    ^ n * (factorial value: (n - 1))
]

"Calculate factorials"
1 to: 10 do: [:i |
    (i asString , "! = " , ((factorial value: i) asString)) println
]`,

        fibonacci: `"Fibonacci sequence"
fib := [:n |
    (n <= 1) ifTrue: [^ n].
    ^ (fib value: (n - 1)) + (fib value: (n - 2))
]

"Print first 15 Fibonacci numbers"
1 to: 15 do: [:i |
    ("F(" , (i asString) , ") = " , ((fib value: i) asString)) println
]`,

        point: `"Point class example"
Point := Object derive: #(x y)

Point extend: [
    self >> moveBy: dx and: dy [
        x := x + dx
        y := y + dy
        ^ self
    ]

    self >> distanceFromOrigin [
        ^ ((x * x) + (y * y)) sqrt
    ]

    self >> toString [
        ^ "Point(" , (x asString) , ", " , (y asString) , ")"
    ]
]

"Create and use a point"
p := Point new
p x: 3 y: 4
p toString println
p distanceFromOrigin println`
    };

    // Load example buttons
    document.querySelectorAll('.toolbar-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const example = btn.dataset.example;
            if (examples[example] && playgroundCode) {
                playgroundCode.value = examples[example];
            }
        });
    });

    // Run button - uses real Harding interpreter
    if (runBtn && output && playgroundCode) {
        runBtn.addEventListener('click', () => {
            const code = playgroundCode.value;
            output.innerHTML = '';

            // Show running indicator
            output.innerHTML = '<div class="output-line">Running...</div>';
            runBtn.disabled = true;

            setTimeout(() => {
                output.innerHTML = '';

                // Check if Harding interpreter is available
                if (typeof Harding === 'undefined' || !Harding.doit) {
                    output.innerHTML = '<div class="output-line error">Error: Harding interpreter not loaded. Please wait a moment and try again.</div>';
                    runBtn.disabled = false;
                    return;
                }

                // Run the code using the real interpreter
                const result = Harding.doit(code);

                // Display result
                if (result) {
                    if (result.startsWith('ERROR:')) {
                        // Show error
                        const div = document.createElement('div');
                        div.className = 'output-line error';
                        div.textContent = result.substring(6).trim();
                        output.appendChild(div);
                    } else {
                        // Show output lines
                        const lines = result.split('\n').filter(line => line.length > 0);
                        if (lines.length === 0) {
                            output.innerHTML = '<div class="output-placeholder">(no output)</div>';
                        } else {
                            lines.forEach(line => {
                                const div = document.createElement('div');
                                div.className = 'output-line output';
                                div.textContent = line;
                                output.appendChild(div);
                            });
                        }
                    }
                } else {
                    output.innerHTML = '<div class="output-placeholder">(no output)</div>';
                }

                runBtn.disabled = false;
            }, 50);
        });
    }

    // Clear button
    if (clearBtn && output) {
        clearBtn.addEventListener('click', () => {
            output.innerHTML = '<div class="output-placeholder">Click "Run" to see the output</div>';
        });
    }

    // ============================================
    // Copy to Clipboard
    // ============================================
    document.querySelectorAll('.copy-btn').forEach(btn => {
        btn.addEventListener('click', async () => {
            const text = btn.dataset.clipboard;
            if (text) {
                try {
                    await navigator.clipboard.writeText(text);
                    btn.classList.add('copied');
                    setTimeout(() => {
                        btn.classList.remove('copied');
                    }, 2000);
                } catch (err) {
                    console.error('Failed to copy:', err);
                }
            }
        });
    });

    // ============================================
    // Smooth Scroll for Anchor Links
    // ============================================
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function(e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                const headerOffset = 80;
                const elementPosition = target.getBoundingClientRect().top;
                const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

                window.scrollTo({
                    top: offsetPosition,
                    behavior: 'smooth'
                });
            }
        });
    });

    // ============================================
    // Navbar scroll effect
    // ============================================
    const navbar = document.querySelector('.navbar');
    let lastScroll = 0;

    window.addEventListener('scroll', () => {
        const currentScroll = window.pageYOffset;

        if (currentScroll > 100) {
            navbar.style.background = 'rgba(15, 23, 41, 0.95)';
        } else {
            navbar.style.background = 'rgba(15, 23, 41, 0.85)';
        }

        lastScroll = currentScroll;
    });
});

// ============================================
// Harding Interpreter Integration
// ============================================

// The Harding interpreter is loaded via harding.js
// It exposes a global 'Harding' object with methods:
// - Harding.doit(code): Returns the result as a string
// - Harding.version(): Returns the version string
// - Harding.isInitialized(): Returns true if ready

// Check if interpreter is loaded
document.addEventListener('hardingReady', () => {
    hardingReady = true;
    console.log('Harding interpreter ready, version:', Harding.version());
});
