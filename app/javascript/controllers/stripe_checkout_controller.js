import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["loading", "paymentElement", "submitButton", "buttonText", "spinner", "message"]
  static values = {
    publishableKey: String,
    clientSecret: String,
    returnUrl: String
  }

  connect() {
    this.initStripe()
  }

  async initStripe() {
    await this.loadStripeJs()

    this.stripe = Stripe(this.publishableKeyValue)

    const appearance = {
      theme: 'stripe',
      variables: {
        colorPrimary: 'oklch(14% 0.005 285.823)',
        colorBackground: '#ffffff',
        colorText: 'oklch(21% 0.006 285.885)',
        colorDanger: '#dc2626',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
        spacingUnit: '4px',
        borderRadius: '8px',
        colorTextSecondary: 'oklch(45% 0 0)',
        colorTextPlaceholder: 'oklch(65% 0 0)'
      },
      rules: {
        '.Input': {
          borderColor: 'oklch(85% 0 0)',
          boxShadow: 'none',
          transition: 'border-color 200ms ease'
        },
        '.Input:focus': {
          borderColor: 'oklch(14% 0.005 285.823)',
          boxShadow: '0 0 0 1px oklch(14% 0.005 285.823)'
        },
        '.Label': {
          fontSize: '14px',
          fontWeight: '400',
          color: 'oklch(21% 0.006 285.885)'
        },
        '.Tab': {
          borderColor: 'oklch(88% 0 0)',
          boxShadow: 'none'
        },
        '.Tab--selected': {
          borderColor: 'oklch(14% 0.005 285.823)',
          boxShadow: '0 0 0 1px oklch(14% 0.005 285.823)'
        },
        '.Tab:hover': {
          borderColor: 'oklch(60% 0 0)'
        }
      }
    }

    this.elements = this.stripe.elements({
      clientSecret: this.clientSecretValue,
      appearance
    })

    const paymentElement = this.elements.create('payment', {
      layout: {
        type: 'accordion',
        defaultCollapsed: false,
        radios: false,
        spacedAccordionItems: false
      },
      wallets: {
        applePay: 'auto',
        googlePay: 'auto'
      },
      defaultValues: {
        billingDetails: {
          address: {
            country: 'US'
          }
        }
      }
    })

    paymentElement.on('ready', () => {
      this.loadingTarget.classList.add('hidden')
      this.paymentElementTarget.classList.remove('hidden')
      this.submitButtonTarget.disabled = false
    })

    paymentElement.mount(this.paymentElementTarget)
  }

  async submit(event) {
    event.preventDefault()

    this.submitButtonTarget.disabled = true
    this.buttonTextTarget.style.display = 'none'
    this.spinnerTarget.style.display = 'inline'

    const { error } = await this.stripe.confirmPayment({
      elements: this.elements,
      confirmParams: {
        return_url: this.returnUrlValue,
      },
    })

    if (error) {
      if (error.type === 'card_error' || error.type === 'validation_error') {
        this.messageTarget.textContent = error.message
      } else {
        this.messageTarget.textContent = 'An unexpected error occurred.'
      }

      this.submitButtonTarget.disabled = false
      this.buttonTextTarget.style.display = 'inline'
      this.spinnerTarget.style.display = 'none'
    }
  }

  loadStripeJs() {
    if (window.Stripe) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const script = document.createElement('script')
      script.src = 'https://js.stripe.com/v3/'
      script.onload = resolve
      script.onerror = reject
      document.head.appendChild(script)
    })
  }
}
