// ============================================
// Harding Website JavaScript
// ============================================

// Global Harding interpreter instance
let hardingReady = false;

const hardingKeywords = new Set([
    'self',
    'super',
    'nil',
    'true',
    'false',
    'class'
]);

const shellCommands = new Set([
    'git',
    'nim',
    'nimble',
    'harding',
    'granite',
    'cd',
    'ls',
    'make'
]);

function escapeHtml(value) {
    return value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function wrapToken(className, value) {
    return `<span class="${className}">${escapeHtml(value)}</span>`;
}

function isWordStart(char) {
    return /[A-Za-z_]/.test(char);
}

function isWordChar(char) {
    return /[A-Za-z0-9_]/.test(char);
}

function isDigit(char) {
    return /[0-9]/.test(char);
}

function findHardingCommentStart(line) {
    for (let i = 0; i < line.length; i += 1) {
        if (line[i] !== '#') {
            continue;
        }

        const prevChar = i > 0 ? line[i - 1] : '';
        const nextChar = i + 1 < line.length ? line[i + 1] : '';
        const startsComment = (i === 0 || /\s/.test(prevChar)) && (nextChar === '' || /\s/.test(nextChar));

        if (startsComment) {
            return i;
        }
    }

    return -1;
}

function readQuotedToken(line, startIndex) {
    const quote = line[startIndex];
    let index = startIndex + 1;

    while (index < line.length) {
        if (line[index] === '\\') {
            index += 2;
            continue;
        }

        if (line[index] === quote) {
            return {
                token: line.slice(startIndex, index + 1),
                end: index + 1
            };
        }

        index += 1;
    }

    return {
        token: line.slice(startIndex),
        end: line.length
    };
}

function highlightHardingLine(line) {
    const commentStart = findHardingCommentStart(line);
    const codePart = commentStart >= 0 ? line.slice(0, commentStart) : line;
    const commentPart = commentStart >= 0 ? line.slice(commentStart) : '';

    let highlighted = '';
    let i = 0;

    while (i < codePart.length) {
        const char = codePart[i];

        if (char === '"' || char === '\'') {
            const quoted = readQuotedToken(codePart, i);
            highlighted += wrapToken('hl-string', quoted.token);
            i = quoted.end;
            continue;
        }

        if (char === '#') {
            const nextChar = i + 1 < codePart.length ? codePart[i + 1] : '';

            if (nextChar === '"' || nextChar === '\'') {
                const quotedSymbol = readQuotedToken(codePart, i + 1);
                highlighted += wrapToken('hl-symbol', codePart.slice(i, quotedSymbol.end));
                i = quotedSymbol.end;
                continue;
            }

            if (isWordStart(nextChar)) {
                let end = i + 2;
                while (end < codePart.length && (isWordChar(codePart[end]) || codePart[end] === ':')) {
                    end += 1;
                }
                highlighted += wrapToken('hl-symbol', codePart.slice(i, end));
                i = end;
                continue;
            }

            highlighted += wrapToken('hl-symbol', char);
            i += 1;
            continue;
        }

        if (isDigit(char)) {
            let end = i + 1;
            if (char === '0' && (codePart[end] === 'x' || codePart[end] === 'X')) {
                end += 1;
                while (end < codePart.length && /[0-9a-fA-F]/.test(codePart[end])) {
                    end += 1;
                }
            } else {
                while (end < codePart.length && /[0-9_.]/.test(codePart[end])) {
                    end += 1;
                }
            }
            highlighted += wrapToken('hl-number', codePart.slice(i, end));
            i = end;
            continue;
        }

        if (isWordStart(char)) {
            let end = i + 1;
            while (end < codePart.length && isWordChar(codePart[end])) {
                end += 1;
            }
            while (end < codePart.length && codePart[end] === ':') {
                end += 1;
            }

            const token = codePart.slice(i, end);

            if (hardingKeywords.has(token.replace(/:+$/, ''))) {
                highlighted += wrapToken('hl-keyword', token);
            } else if (token.endsWith(':')) {
                highlighted += wrapToken('hl-selector', token);
            } else if (/^[A-Z]/.test(token)) {
                highlighted += wrapToken('hl-type', token);
            } else {
                highlighted += escapeHtml(token);
            }

            i = end;
            continue;
        }

        const twoCharOperator = codePart.slice(i, i + 2);
        if ([':=', '>>', '<=', '>=', '==', '!=', '->', '//', '=>'].includes(twoCharOperator)) {
            highlighted += wrapToken('hl-operator', twoCharOperator);
            i += 2;
            continue;
        }

        if ('+-*/=<>&|^%;'.includes(char)) {
            highlighted += wrapToken('hl-operator', char);
            i += 1;
            continue;
        }

        if ('()[]{}.,'.includes(char)) {
            highlighted += wrapToken('hl-punctuation', char);
            i += 1;
            continue;
        }

        highlighted += escapeHtml(char);
        i += 1;
    }

    if (commentPart.length > 0) {
        highlighted += wrapToken('hl-comment', commentPart);
    }

    return highlighted;
}

function highlightHarding(source) {
    return source.split('\n').map(highlightHardingLine).join('\n');
}

function highlightShell(source) {
    return source.split('\n').map(line => {
        const commentStart = line.indexOf('#');
        const codePart = commentStart >= 0 ? line.slice(0, commentStart) : line;
        const commentPart = commentStart >= 0 ? line.slice(commentStart) : '';
        const prefixMatch = codePart.match(/^\s*\$\s*/);

        let highlighted = '';
        let remaining = codePart;

        if (prefixMatch) {
            highlighted += wrapToken('hl-operator', prefixMatch[0]);
            remaining = codePart.slice(prefixMatch[0].length);
        }

        const parts = remaining.split(/(\s+)/);
        const firstWordIndex = parts.findIndex(part => part.trim().length > 0);

        highlighted += parts.map((part, index) => {
            if (part.trim().length === 0) {
                return escapeHtml(part);
            }

            if (index === firstWordIndex && shellCommands.has(part)) {
                return wrapToken('hl-keyword', part);
            }

            if (part.startsWith('-')) {
                return wrapToken('hl-selector', part);
            }

            if (/^[0-9]+$/.test(part)) {
                return wrapToken('hl-number', part);
            }

            return escapeHtml(part);
        }).join('');

        if (commentPart.length > 0) {
            highlighted += wrapToken('hl-comment', commentPart);
        }

        return highlighted;
    }).join('\n');
}

function detectSnippetLanguage(source) {
    if (/\b(:=|ifTrue:|ifFalse:|derive|extend:|on:do:|perform:|super|self|Object)\b/.test(source) || />>|#\(|\[:/.test(source)) {
        return 'harding';
    }

    if (/^\s*\$\s+/m.test(source) || /^\s*(git|nim|nimble|harding|granite)\b/m.test(source)) {
        return 'shell';
    }

    return null;
}

function applySyntaxHighlighting() {
    document.querySelectorAll('pre code').forEach(code => {
        const pre = code.closest('pre');
        if (!pre) {
            return;
        }

        const source = code.textContent.replace(/\r\n/g, '\n');
        if (source.trim().length === 0) {
            return;
        }

        const language = code.dataset.lang || pre.dataset.lang || detectSnippetLanguage(source);
        let highlighted = null;

        if (language === 'harding') {
            highlighted = highlightHarding(source);
        } else if (language === 'shell') {
            highlighted = highlightShell(source);
        }

        if (!highlighted) {
            return;
        }

        const lines = highlighted.split('\n');
        code.innerHTML = lines
            .map(line => `<span class="code-line">${line.length > 0 ? line : '&nbsp;'}</span>`)
            .join('');

        code.classList.add('syntax-enhanced');
        pre.classList.add('syntax-enhanced');

        if (lines.length >= 6) {
            pre.classList.add('show-line-numbers');
        }
    });
}

// Load Harding interpreter
document.addEventListener('DOMContentLoaded', () => {
    applySyntaxHighlighting();

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
