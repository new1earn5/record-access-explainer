import { createElement } from 'lwc';
import RaaReasonDetail from 'c/raaReasonDetail';

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-raa-reason-detail', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function createComponent(reasons) {
        const element = createElement('c-raa-reason-detail', {
            is: RaaReasonDetail
        });
        element.userName = 'Jane Doe';
        element.username = 'jane@example.com';
        element.reasons = reasons;
        document.body.appendChild(element);
        return element;
    }

    it('shows the empty state when there are no reasons', async () => {
        const element = createComponent([]);
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'No detected reasons are available'
        );
        expect(element.shadowRoot.querySelector('.raa-reason-card')).toBeNull();
    });

    it('splits the grant path into chips, one per arrow-separated segment', async () => {
        const element = createComponent([
            {
                recordId: 'reason001',
                category: 'Role Hierarchy',
                accessLevel: 'Read',
                confidence: 'Medium',
                isDirect: false,
                sourceName: 'Role',
                rowCause: 'Role',
                grantPath: 'Owner -> Manager -> VP of Sales',
                explanation: 'Access flows up the role hierarchy.',
                evidence: 'RoleId chain'
            }
        ]);
        await flushPromises();

        const chips = element.shadowRoot.querySelectorAll('.raa-path-chip');
        expect(chips).toHaveLength(3);
        expect(chips[0].textContent).toBe('Owner');
        expect(chips[1].textContent).toBe('Manager');
        expect(chips[2].textContent).toBe('VP of Sales');
    });

    it('renders no path chips when the grant path is empty', async () => {
        const element = createComponent([
            {
                recordId: 'reason002',
                category: 'Ownership',
                accessLevel: 'Full Access',
                confidence: 'High',
                isDirect: true,
                sourceName: 'User',
                rowCause: null,
                grantPath: null,
                explanation: 'User owns this record.',
                evidence: null
            }
        ]);
        await flushPromises();

        expect(
            element.shadowRoot.querySelectorAll('.raa-path-chip')
        ).toHaveLength(0);
        expect(element.shadowRoot.querySelector('details')).toBeNull();
    });

    it('dispatches a close event when the close button is clicked', async () => {
        const element = createComponent([]);
        await flushPromises();

        const closeHandler = jest.fn();
        element.addEventListener('close', closeHandler);
        element.shadowRoot.querySelector('footer button').click();

        expect(closeHandler).toHaveBeenCalled();
    });
});
